#include "GameData.h"

#include "robomaster.pb.h"

#include <algorithm>
#include <iterator>

namespace {
constexpr qint64 dashboardPacketTimeoutMs = 2500;
constexpr qint64 dashboardNoticeTimeoutMs = 12000;
constexpr int heavyTransitionMs = 1000;

QString teamName(bool red) {
  return red ? QStringLiteral("红方") : QStringLiteral("蓝方");
}

QString robotName(int slot) {
  switch (slot) {
  case 1: return QStringLiteral("重装");
  case 6: return QStringLiteral("空中系统");
  case 7: return QStringLiteral("哨兵");
  default: return QStringLiteral("步兵");
  }
}

QString effectName(int type, int level) {
  switch (type) {
  case 1: return QStringLiteral("攻击 +%1%").arg(level);
  case 2: return level < 0 ? QStringLiteral("易伤 %1%").arg(-qint64(level))
                           : QStringLiteral("防御 +%1%").arg(level);
  case 3: return QStringLiteral("冷却 +%1/s").arg(level);
  case 4: return QStringLiteral("功率 +%1%").arg(level);
  case 5: return QStringLiteral("回血 +%1%").arg(level);
  case 6: return QStringLiteral("可兑换发弹量");
  default: return QStringLiteral("地形增益预备");
  }
}

QString officialReason(int reason) {
  switch (reason) {
  case 1: return QStringLiteral("基地被击毁");
  case 2: return QStringLiteral("控制度");
  case 3: return QStringLiteral("累计伤害");
  case 4: return QStringLiteral("剩余血量");
  case 5: return QStringLiteral("双方打平");
  case 6: return QStringLiteral("异常终止");
  case 7: return QStringLiteral("裁判判定");
  default: return {};
  }
}
}

void GameData::resetDashboardSeat(bool teamChanged) {
  m_dashboardHeatAt = 0;
  m_dashboardHeatPenaltyUntil = 0;
  if (uses2027Protocol())
    resetDashboardRespawn();
  m_dashboardInjuryBaseline.clear();
  m_dashboardInjuryChanges.clear();
  m_dashboardInjuryAt = 0;
  if (teamChanged) {
    m_dashboardAmmo.clear();
    m_dashboardSentry.clear();
    m_dashboardPreviousEconomy = -1;
    m_dashboardEconomyAt = 0;
  }
}

void GameData::resetDashboardRespawn() {
  m_dashboardRespawn.clear();
  m_paidRespawnPowerBoostEndTime = {};
  if (m_lastRespawnStatus.isEmpty())
    return;
  m_lastRespawnStatus.clear();
  m_lastPendingRespawn = false;
  m_lastRespawnProgress = 0;
  m_lastRespawnTotal = 0;
  emit robotRespawnStatusUpdated(m_lastRespawnStatus);
}

void GameData::resetDashboardRound() {
  resetDashboardSeat(true);
  m_dashboardReadings.clear();
  m_dashboardUnitsAt = 0;
  m_dashboardMaxHeat.clear();
  m_dashboardBuffTimes.clear();
  m_dashboardRedDarts.clear();
  m_dashboardBlueDarts.clear();
  const bool currentHeavyChanged = m_dashboardHeavy.contains(m_currentRobotId);
  m_dashboardHeavy.clear();
  m_dashboardHeavyElapsed = -1;
  if (currentHeavyChanged)
    emit myRobotUpdated();
  if (uses2027Protocol()) {
    for (auto &robot : m_robots)
      robot.hasTabGlobalSnapshot = false;
  }
}

void GameData::recordDashboardUnits(const robomaster::GlobalUnitStatus &data) {
  const bool red = m_currentRobotId < 100;
  const QString ally = red ? QStringLiteral("red") : QStringLiteral("blue");
  const QString enemy = red ? QStringLiteral("blue") : QStringLiteral("red");
  auto save = [this](const QString &key, bool present, quint32 value) {
    if (present)
      m_dashboardReadings.insert(key, value);
  };
  save(ally + "Damage", data.has_total_damage_ally(), data.total_damage_ally());
  save(enemy + "Damage", data.has_total_damage_enemy(), data.total_damage_enemy());
  save(ally + "Control", data.has_total_cp_ally(), data.total_cp_ally());
  save(enemy + "Control", data.has_total_cp_enemy(), data.total_cp_enemy());
  save(ally + "BaseHp", data.has_base_health(), data.base_health());
  save(enemy + "BaseHp", data.has_enemy_base_health(), data.enemy_base_health());
  save(ally + "BaseStatus", data.has_base_status(), data.base_status());
  save(enemy + "BaseStatus", data.has_enemy_base_status(), data.enemy_base_status());
  save("redOutpostHp", data.has_outpost_health(), data.outpost_health());
  save("blueOutpostHp", data.has_enemy_outpost_health(), data.enemy_outpost_health());

  if (tracksHeavyInstallation() && matchProfile() == RM::MatchProfile::Rmuc2027) {
    const int allyId = red ? 1 : 101;
    for (const int id : {1, 101}) {
      auto &heavy = m_dashboardHeavy[id];
      const qint64 sign = id == allyId ? 1 : -1;
      if (data.has_base_health() && data.has_enemy_base_health()) {
        const qint64 deficit = sign * (qint64(data.enemy_base_health()) - data.base_health());
        heavy.peakBaseDeficit = qMax(heavy.peakBaseDeficit, deficit);
      }
      if (data.has_total_cp_ally() && data.has_total_cp_enemy()) {
        const qint64 deficit = sign * (qint64(data.total_cp_enemy()) - data.total_cp_ally());
        heavy.peakControlDeficit = qMax(heavy.peakControlDeficit, deficit);
      }
    }
    refreshDashboardHeavyUnlocks();
  }

  const int slotsPerSide = static_cast<int>(std::size(RM::globalUnitSlots2027));
  if (data.robot_health_size() == slotsPerSide * 2) {
    int allyHp = 0;
    int enemyHp = 0;
    for (int i = 0; i < slotsPerSide; ++i) {
      const int slot = RM::globalUnitSlots2027[i];
      if (matchProfile() == RM::MatchProfile::Rmul1v1 ? slot != 3 :
          matchProfile() == RM::MatchProfile::Rmul3v3 && slot == 4)
        continue;
      allyHp += data.robot_health(i);
      enemyHp += data.robot_health(i + slotsPerSide);
    }
    m_dashboardReadings.insert(ally + "Health", allyHp);
    m_dashboardReadings.insert(enemy + "Health", enemyHp);
  }
  for (int i = 0; i < qMin(slotsPerSide, data.robot_bullets_size()); ++i) {
    const int id = (red ? 0 : 100) + RM::globalUnitSlots2027[i];
    if (data.robot_bullets(i) < 0) {
      m_dashboardAmmo.remove(id);
      continue;
    }
    auto &reading = m_dashboardAmmo[id];
    reading.first = data.robot_bullets(i);
    reading.second = qMax(reading.second, reading.first);
  }
  if (data.robot_health_size() == slotsPerSide * 2 || data.has_total_cp_ally() ||
      data.has_total_damage_ally() || data.has_base_health()) {
    m_dashboardUnitsAt = QDateTime::currentMSecsSinceEpoch();
  }
}

void GameData::recordDashboardInjury(const robomaster::RobotInjuryStat &data) {
  const QVariantMap reading{
    {QStringLiteral("42 mm"), data.large_projectile_damage()},
    {QStringLiteral("17 mm"), data.small_projectile_damage()},
    {QStringLiteral("模块离线"), data.module_offline_damage()},
    {QStringLiteral("异常离线"), data.offline_damage()},
    {QStringLiteral("判罚"), data.penalty_damage()},
    {QStringLiteral("飞镖溅射"), data.dart_splash_damage()},
    {QStringLiteral("撞击"), data.collision_damage()},
    {QStringLiteral("裁判处置"), data.server_kill_damage()}
  };
  QVariantList changes;
  if (!m_dashboardInjuryBaseline.isEmpty()) {
    for (auto it = reading.cbegin(); it != reading.cend(); ++it) {
      const qint64 delta = it.value().toLongLong() - m_dashboardInjuryBaseline.value(it.key()).toLongLong();
      if (delta < 0) {
        changes.clear();
        m_dashboardInjuryChanges.clear();
        break;
      }
      if (delta > 0)
        changes.append(QVariantMap{{"label", it.key()}, {"value", -delta}});
    }
  }
  m_dashboardInjuryBaseline = reading;
  if (!changes.isEmpty()) {
    m_dashboardInjuryChanges = changes;
    m_dashboardInjuryAt = QDateTime::currentMSecsSinceEpoch();
  }
}

void GameData::updateDashboardSentry(const robomaster::SentryStatusSync &data) {
  if (!uses2027Protocol() || !data.has_posture_id() ||
      data.posture_id() < 1 || data.posture_id() > 3)
    return;
  const int previous = m_dashboardSentry.value("mode").toInt();
  if (previous && previous != int(data.posture_id()) && m_gameState.gameProgress == GameStage::BATTLE)
    m_dashboardSentry.insert("changedAt", m_gameState.gameTime);
  m_dashboardSentry.insert("mode", data.posture_id());
  if (data.has_is_weakened())
    m_dashboardSentry.insert("weakened", data.is_weakened());
  if (data.has_is_powered())
    m_dashboardSentry.insert("powered", data.is_powered());
}

bool GameData::tracksHeavyInstallation() const {
  return (matchProfile() == RM::MatchProfile::Rmuc2027 ||
          matchProfile() == RM::MatchProfile::Rmul3v3) &&
         m_gameState.gameProgress == GameStage::BATTLE;
}

bool GameData::hasLiveHeavyStatusContext() const {
  return tracksHeavyInstallation() && m_gameState.currentRound > 0 &&
         m_dashboardHeavyElapsed >= 0 && m_dashboardStatusAt > 0 &&
         QDateTime::currentMSecsSinceEpoch() - m_dashboardStatusAt <= dashboardPacketTimeoutMs;
}

void GameData::grantDashboardHeavyPermission(int robotId) {
  auto &heavy = m_dashboardHeavy[robotId];
  if (heavy.permission == 1)
    return;
  heavy.permission = 1;
  if (robotId == m_currentRobotId)
    emit myRobotUpdated();
  emitDataChanged();
}

void GameData::refreshDashboardHeavyUnlocks() {
  if (matchProfile() != RM::MatchProfile::Rmuc2027 || m_dashboardHeavyElapsed < 0)
    return;
  for (const int id : {1, 101}) {
    const auto &heavy = m_dashboardHeavy[id];
    // RMUC §5.7.1 uses the highest deficit for each measure independently.
    // Multiply by 150 to compare with the fractional threshold exactly.
    const qint64 threshold = 300 * 150 - 3 * heavy.peakBaseDeficit - 100 * heavy.peakControlDeficit;
    if (qint64(m_dashboardHeavyElapsed) * 150 >= threshold)
      grantDashboardHeavyPermission(id);
  }
}

void GameData::markDashboardHeavyInstalled(int robotId, int animationAgeMs) {
  if (!tracksHeavyInstallation() || !getRobotById(robotId))
    return;
  auto &heavy = m_dashboardHeavy[robotId];
  if (heavy.installedAtMs > 0)
    return;
  heavy.permission = 1;
  heavy.installedAtMs = QDateTime::currentMSecsSinceEpoch() -
      qBound(0, animationAgeMs, heavyTransitionMs);
  if (robotId == m_currentRobotId)
    emit myRobotUpdated();
  emitDataChanged();
}

bool GameData::recordDashboardHeavyInstallation(const QString &param) {
  // V1.0.0 does not define a team or robot ID parameter for Event 16.
  const int ownHeavyId = m_currentRobotId < 100 ? 1 : 101;
  if (!tracksHeavyInstallation() || param.trimmed() != QString::number(ownHeavyId))
    return false;
  markDashboardHeavyInstalled(ownHeavyId);
  return true;
}

QJsonObject GameData::teamHeavyStatus() const {
  if (!hasLiveHeavyStatusContext() || m_currentRobotId % 100 != 1)
    return {};
  const auto heavy = m_dashboardHeavy.value(m_currentRobotId);
  if (heavy.permission != 1)
    return {};
  const qint64 age = heavy.installedAtMs > 0
      ? std::clamp<qint64>(QDateTime::currentMSecsSinceEpoch() - heavy.installedAtMs,
                           0, heavyTransitionMs)
      : -1;
  return {{QStringLiteral("profile"), int(matchProfile())},
          {QStringLiteral("round"), int(m_gameState.currentRound)},
          {QStringLiteral("elapsed"), m_dashboardHeavyElapsed},
          {QStringLiteral("robot"), int(m_currentRobotId)},
          {QStringLiteral("installation_age_ms"), int(age)}};
}

void GameData::updateTeamHeavyStatus(const QJsonObject &status) {
  if (!hasLiveHeavyStatusContext())
    return;
  const int robotId = status.value(QStringLiteral("robot")).toInt(-1);
  const int elapsed = status.value(QStringLiteral("elapsed")).toInt(-1);
  const int age = status.value(QStringLiteral("installation_age_ms")).toInt(-2);
  if (robotId != (m_currentRobotId >= 100 ? 101 : 1) ||
      status.value(QStringLiteral("profile")).toInt(-1) != int(matchProfile()) ||
      status.value(QStringLiteral("round")).toInt(-1) != m_gameState.currentRound ||
      elapsed < 0 || qAbs(qint64(elapsed) - m_dashboardHeavyElapsed) > 3 ||
      age < -1 || age > heavyTransitionMs)
    return;
  if (age >= 0)
    markDashboardHeavyInstalled(robotId, age);
  else
    grantDashboardHeavyPermission(robotId);
}

QVariantMap GameData::dashboardHeavyState(int robotId) const {
  const auto state = m_dashboardHeavy.constFind(robotId);
  if (state == m_dashboardHeavy.cend())
    return {};
  QVariantMap result;
  if (state->permission >= 0)
    result.insert(QStringLiteral("allowed"), state->permission == 1);
  if (state->installedAtMs > 0)
    result.insert(QStringLiteral("installedAt"), state->installedAtMs);
  return result;
}

QVariantMap GameData::dashboardData() const {
  if (!uses2027Protocol())
    return {};
  const auto now = QDateTime::currentMSecsSinceEpoch();
  const bool battle = m_gameState.gameProgress == GameStage::BATTLE;
  const bool settled = m_gameState.gameProgress == GameStage::SETTLEMENT;
  const bool statusFresh = m_dashboardStatusAt > 0 && now - m_dashboardStatusAt <= dashboardPacketTimeoutMs;
  const bool unitsFresh = m_dashboardUnitsAt > 0 && now - m_dashboardUnitsAt <= dashboardPacketTimeoutMs;
  const bool redPerspective = m_currentRobotId < 100;
  QVariantMap result = m_dashboardReadings;
  int leadingSide = 0;
  QString leadText = QStringLiteral("均势");
  QString reason;
  auto compare = [&](const QString &key, const QString &name) {
    const QVariant red = m_dashboardReadings.value(QStringLiteral("red") + key);
    const QVariant blue = m_dashboardReadings.value(QStringLiteral("blue") + key);
    if (!red.isValid() || !blue.isValid()) {
      leadText = QStringLiteral("等待") + name;
      return true;
    }
    if (red.toLongLong() == blue.toLongLong())
      return false;
    leadingSide = red.toLongLong() > blue.toLongLong() ? 1 : 2;
    leadText = teamName(leadingSide == 1) + QStringLiteral("领先");
    reason = QStringLiteral("%1 %2 ∶ %3").arg(name, red.toString(), blue.toString());
    return true;
  };
  if (settled && m_officialWinner <= 2) {
    leadingSide = m_officialWinner;
    leadText = leadingSide == 0 ? QStringLiteral("平局")
                                : teamName(leadingSide == 1) + QStringLiteral("获胜");
    reason = officialReason(m_officialEndReason);
  } else if (settled) {
    leadText = QStringLiteral("等待裁判结算");
  } else if (battle && (!statusFresh || !unitsFresh)) {
    leadText = QStringLiteral("等待胜负数据");
  } else if (battle) {
    const auto redBase = m_dashboardReadings.value("redBaseHp");
    const auto blueBase = m_dashboardReadings.value("blueBaseHp");
    if (hasBases() && (!redBase.isValid() || !blueBase.isValid())) {
      leadText = QStringLiteral("等待基地血量");
    } else if (hasBases() && (redBase.toInt() == 0 || blueBase.toInt() == 0)) {
      compare("BaseHp", QStringLiteral("基地血量"));
    } else if (hasControlPoints()) {
      if (!compare("Control", QStringLiteral("控制度")) && !compare("Damage", QStringLiteral("累计伤害")))
        compare("Health", QStringLiteral("剩余血量"));
    } else if (!compare("Health", QStringLiteral("剩余血量"))) {
      reason = QStringLiteral("同血量时以裁判结算为准");
    }
  }

  QVariantList boards[2];
  for (const auto &robot : m_robots) {
    const int id = robot.robotId;
    const int slot = id % 100;
    const bool red = id < 100;
    const bool ownSeat = id == m_currentRobotId;
    const bool currentHeat = ownSeat && m_dashboardHeatAt > 0 &&
        now - m_dashboardHeatAt <= dashboardPacketTimeoutMs;
    QVariantMap card{{"number", slot}, {"id", id}, {"name", robotName(slot)}, {"selected", ownSeat}};
    if (slot == 1 && red == redPerspective)
      card.insert(QStringLiteral("heavy"), dashboardHeavyState(id));
    if (slot != 6 && (robot.hasTabGlobalSnapshot || currentHeat)) {
      card.insert("hp", robot.hasTabGlobalSnapshot ? robot.tabGlobalCurrentHP : robot.currentHP);
      if (robot.tabStaticConnected && robot.maxHP > 0)
        card.insert("maxHp", qMax(robot.maxHP, robot.currentRoundMaxHP));
    }
    if (slot != 6 && robot.tabStaticConnected) {
      if (robot.maxPower > 0)
        card.insert("maxPower", robot.maxPower);
      if (robot.heatLimit > 0)
        card.insert("heatLimit", robot.heatLimit);
      if (robot.coolingValue > 0)
        card.insert("heatCooling", robot.coolingValue);
    }
    const auto ammo = m_dashboardAmmo.constFind(id);
    if (ammo != m_dashboardAmmo.cend() && red == redPerspective) {
      card.insert("ammo", ammo->first);
      card.insert("ammoPeak", ammo->second);
    }
    if (currentHeat && m_dashboardMaxHeat.contains(id)) {
      card.insert("heat", m_dashboardHeat);
      card.insert("maxHeat", m_dashboardMaxHeat.value(id));
      card.insert("heatPenalty", now < m_dashboardHeatPenaltyUntil);
    }
    if (ownSeat && battle && m_dashboardRespawn.value("is_pending_respawn").toBool()) {
      const int total = m_dashboardRespawn.value("total_respawn_progress").toInt();
      if (total > 0) {
        card.insert("respawnTotal", total);
        card.insert("respawnLeft", total - qBound(0, m_dashboardRespawn.value("current_respawn_progress").toInt(), total));
      }
    }
    if (slot == 7 && red == redPerspective && !m_dashboardSentry.isEmpty()) {
      QVariantMap sentry = m_dashboardSentry;
      if (sentry.contains("changedAt")) {
        const int elapsed = qMax(0, sentry.take("changedAt").toInt() - m_gameState.gameTime);
        sentry.insert("cooldown", qMax(0, 5 - elapsed));
      }
      card.insert("sentry", sentry);
    }
    QVariantList effects;
    if (battle && card.value("hp").toInt() > 0) {
      for (const int type : {2, 5, 3, 1, 4, 6, 7}) {
        const auto observed = m_dashboardBuffTimes.constFind(id * 8 + type);
        if (observed == m_dashboardBuffTimes.cend())
          continue;
        const auto *buff = robot.buffs.byType(type);
        const int left = qMax(0, int(buff->leftTimeAtSync) - qMax(0, *observed - m_gameState.gameTime));
        if (left > 0) {
          effects.append(QVariantMap{{"type", type}, {"label", effectName(type, buff->level)},
                                    {"left", left}, {"total", qMax(int(buff->maxTime), left)},
                                    {"vulnerable", type == 2 && buff->level < 0}});
        }
      }
    }
    card.insert("effects", effects);
    boards[red ? 0 : 1].append(card);
  }
  result.insert("redRobots", boards[0]);
  result.insert("blueRobots", boards[1]);
  result.insert("playerName", teamName(redPerspective) + QStringLiteral(" %1 号 ").arg(m_currentRobotId % 100) +
                               robotName(m_currentRobotId % 100));
  result.insert("leadingSide", leadingSide);
  result.insert("leadText", leadText);
  result.insert("leadReason", reason);
  result.insert("statusFresh", statusFresh);
  result.insert("redDarts", m_dashboardRedDarts);
  result.insert("blueDarts", m_dashboardBlueDarts);
  if (now - m_dashboardInjuryAt <= dashboardNoticeTimeoutMs)
    result.insert("injury", m_dashboardInjuryChanges);
  if (m_dashboardPreviousEconomy >= 0)
    result.insert("economyReported", true);
  if (now - m_dashboardEconomyAt <= dashboardNoticeTimeoutMs)
    result.insert("economyDelta", m_dashboardEconomyDelta);
  return result;
}
