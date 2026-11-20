#include "core/GameData.h"
#include "core/GameConstants.h"
#include "network/Protocol.h"
#include "network/NetworkManager.h"
#include "robomaster.pb.h"
#include <QImageReader>
#include <QScopeGuard>
#include <QtTest>

namespace {

QStringList *g_runeStatusLogMessages = nullptr;

void captureRuneStatusLog(QtMsgType type, const QMessageLogContext &,
                          const QString &message) {
  if (type == QtInfoMsg && g_runeStatusLogMessages &&
      message.startsWith(
          QStringLiteral("[RuneVoice] RuneStatusSync status changed"))) {
    g_runeStatusLogMessages->append(message);
  }
}

} // namespace

/**
 * @brief GameData 单元测试类
 *
 * 测试 GameData 类的核心功能，包括：
 * 1. 机器人数据的更新与检索
 * 2. 基地数据的更新
 * 3. 比赛状态的更新
 * 4. 信号的正确发射
 */
class TestGameData : public QObject {
  Q_OBJECT

private slots:
  /**
   * @brief 初始化测试
   * 验证 GameData 初始化后的默认状态是否正确。
   */
  void initTestCase() {
    GameData gameData;

    // 验证默认机器人数量
    QCOMPARE(gameData.getAllRobots().size(),
             12); // 每方初始化 6 台可见机器人（1、2、3、4、6、7）；
                  // 当前客户端界面不显示 5/105。
    QVERIFY(gameData.getRobotById(5) == nullptr);
    QVERIFY(gameData.getRobotById(105) == nullptr);

    // 验证默认比赛阶段
    QCOMPARE(gameData.getCurrentStage(), GameStage::NOT_STARTED);

    // 验证默认比赛时间
    QCOMPARE(gameData.getGameTime(), 420);
  }

  /**
   * @brief 测试机器人数据更新
   * 模拟接收到机器人状态包，验证数据是否正确更新。
   */
  void testUpdateRobotData() {
    GameData gameData;

    // 构造模拟数据
    robomaster::RobotStatus statusMsg;
    statusMsg.set_id(1); // 红方英雄
    statusMsg.set_hp(150);
    statusMsg.set_max_hp(200);
    statusMsg.set_heat(50);
    statusMsg.set_heat_limit(100);

    // 监听信号
    QSignalSpy spy(&gameData, &GameData::robotDataUpdated);

    // 执行更新
    gameData.updateRobotData(statusMsg);

    // 验证信号是否发射
    QCOMPARE(spy.count(), 1);
    QList<QVariant> arguments = spy.takeFirst();
    QCOMPARE(arguments.at(0).toInt(), 1);

    // 验证数据是否更新
    const RobotData *robot = gameData.getRobotById(1);
    QVERIFY(robot != nullptr);
    QCOMPARE(robot->currentHP, 150);
    QCOMPARE(robot->maxHP, 200);
    QCOMPARE(robot->currentHeat, 50);
  }

  void test2027UnitStatus_data() {
    QTest::addColumn<bool>("blue");
    QTest::newRow("red") << false;
    QTest::newRow("blue") << true;
  }

  void test2027UnitStatus() {
    QFETCH(bool, blue);
    GameData gameData;
    gameData.setMatchProfile(RM::MatchProfile::Rmuc2027);
    gameData.setCurrentRobotId(blue ? 103 : 3);

    QCOMPARE(gameData.redBaseMaxHealth(), 10000);
    QCOMPARE(gameData.blueOutpostMaxHealth(), 1000);
    QVERIFY(!gameData.territoryStatus().contains("redOutpostHp"));

    // Official field numbers, decoded independently of the generating schema.
    const QByteArray wire = QByteArray::fromHex(
        "0801100118022054280330043801400148285004"
        "5a080b0c0d0e151617186208900114171c000000"
        "7807800108");
    robomaster::GlobalUnitStatus status;
    QVERIFY(status.ParseFromArray(wire.constData(), wire.size()));
    // Ally has four ammo entries. Extra entries must never populate enemy ammo.
    status.clear_robot_bullets();
    for (int ammo : {144, 20, 23, 28, 99, 99, 99, 99})
      status.add_robot_bullets(ammo);
    gameData.updateGlobalUnitStatus(status);

    QCOMPARE(gameData.territoryStatus().value("redOutpostHp").toInt(), 84);
    QCOMPARE(gameData.territoryStatus().value("blueOutpostHp").toInt(), 40);
    QCOMPARE(gameData.territoryStatus().value("redBaseHp").toInt(), blue ? 4 : 1);
    QCOMPARE(gameData.territoryStatus().value("blueBaseHp").toInt(), blue ? 1 : 4);
    QCOMPARE(gameData.getRedOutpost().currentHP, 84);
    QCOMPARE(gameData.getBlueOutpost().currentHP, 40);
    QCOMPARE(gameData.getRedOutpost().status, 0);
    QCOMPARE(gameData.getBlueOutpost().status, 0);
    QCOMPARE(gameData.getRedOutpost().isDestroyed, false);
    QVERIFY(gameData.getRobotById(2) == nullptr);
    QCOMPARE(gameData.getRobotById(blue ? 103 : 3)->currentHP, 12);
    QCOMPARE(gameData.getRobotById(blue ? 104 : 4)->currentHP, 13);
    QCOMPARE(gameData.getRobotById(blue ? 107 : 7)->currentHP, 14);
    QCOMPARE(gameData.getRobotById(blue ? 3 : 103)->currentHP, 22);
    QCOMPARE(gameData.getRobotById(blue ? 103 : 3)->allowedAmmo17mm, 20);
    QCOMPARE(gameData.getRobotById(blue ? 3 : 103)->allowedAmmo17mm, 0);
    const auto allyRows = blue ? gameData.getBlueRobotsDataQml()
                               : gameData.getRedRobotsDataQml();
    QCOMPARE(allyRows.size(), 5);
    QCOMPARE(allyRows.first().toMap().value("name").toString(), QStringLiteral("重装"));
    status.set_robot_health(0, 0);
    gameData.updateGlobalUnitStatus(status);
    const auto updatedRows = blue ? gameData.getBlueRobotsDataQml()
                                  : gameData.getRedRobotsDataQml();
    const auto deadRow = updatedRows.first().toMap();
    QVERIFY(deadRow.value("hpReported").toBool());
    QCOMPARE(deadRow.value("currentHP").toInt(), 0);
    QCOMPARE(gameData.territoryStatus().value("redPoints").toInt(), blue ? 8 : 7);
    QCOMPARE(gameData.territoryStatus().value("bluePoints").toInt(), blue ? 7 : 8);

    robomaster::GlobalUnitStatus partial;
    partial.set_outpost_health(0);
    partial.set_total_cp_ally(0);
    gameData.updateGlobalUnitStatus(partial);
    QCOMPARE(gameData.getRedOutpost().isDestroyed, true);
    QVERIFY(gameData.territoryStatus().contains("redOutpostHp"));
    QCOMPARE(gameData.territoryStatus().value("redOutpostHp").toInt(), 0);
    QCOMPARE(gameData.getBlueOutpost().currentHP, 40);
    QCOMPARE(gameData.territoryStatus().value(blue ? "bluePoints" : "redPoints").toInt(), 0);
    QCOMPARE(gameData.getRobotById(blue ? 103 : 3)->currentHP, 12);

    robomaster::GlobalUnitStatus rebuilt;
    rebuilt.set_outpost_health(500);
    rebuilt.set_outpost_status(blue ? 1 : 4);
    gameData.updateGlobalUnitStatus(rebuilt);
    QVERIFY(!gameData.getRedOutpost().isDestroyed);
    QCOMPARE(gameData.getRedOutpost().currentHP, 500);
    QCOMPARE(gameData.redOutpostMaxHealth(), 1000);
    const QVariantMap territory = gameData.territoryStatus();
    QCOMPARE(territory.value("redOutpostHp").toInt(), 500);
    QCOMPARE(territory.value("redOutpostControl").toInt(), blue ? 1 : 4);
    QVERIFY(territory.contains("redOutpostOwnerRed"));
    QCOMPARE(territory.value("redOutpostOwnerRed").toBool(), false);
  }

  void test2027FieldProgressAndBuffTimers() {
    GameData gameData;
    gameData.setMatchProfile(RM::MatchProfile::Rmuc2027);
    gameData.setCurrentRobotId(3);

    robomaster::GlobalSpecialMechanism progress;
    progress.add_mechanism_id(3);
    progress.add_mechanism_time_sec(-4);
    progress.add_mechanism_id(6);
    progress.add_mechanism_time_sec(2);
    progress.add_mechanism_id(1);
    progress.add_mechanism_time_sec(7);
    progress.add_mechanism_id(2);
    progress.add_mechanism_time_sec(3);
    gameData.updateGlobalSpecialMechanism(progress);
    QCOMPARE(gameData.territoryStatus().value("redOutpostProgressSec").toInt(), -4);
    QCOMPARE(gameData.territoryStatus().value("blueBaseProgressSec").toInt(), 2);
    QCOMPARE(gameData.territoryStatus().value("redFortressRemainingSec").toInt(), 7);
    QCOMPARE(gameData.territoryStatus().value("blueFortressRemainingSec").toInt(), 3);
    gameData.setCurrentRobotId(103);
    gameData.updateGlobalSpecialMechanism(progress);
    QCOMPARE(gameData.territoryStatus().value("redFortressRemainingSec").toInt(), 3);
    QCOMPARE(gameData.territoryStatus().value("blueFortressRemainingSec").toInt(), 7);
    gameData.updateGlobalSpecialMechanism(robomaster::GlobalSpecialMechanism());
    QVERIFY(!gameData.territoryStatus().contains("redOutpostProgressSec"));
    QVERIFY(!gameData.territoryStatus().contains("redFortressRemainingSec"));
    QVERIFY(!gameData.territoryStatus().contains("blueFortressRemainingSec"));
    gameData.setCurrentRobotId(3);

    robomaster::Buff buff;
    buff.set_robot_id(3);
    buff.set_buff_type(2);
    buff.set_buff_level(25);
    buff.set_buff_max_time(30);
    buff.set_buff_left_time(19);
    gameData.updateBuff(buff);
    auto defense = gameData.buffTimedData().value("defenseOrVulnerability").toMap();
    QCOMPARE(defense.value("level").toInt(), 25);
    QCOMPARE(defense.value("leftTime").toInt(), 19);

    buff.set_buff_type(7);
    buff.set_buff_level(1);
    buff.set_buff_max_time(5);
    buff.set_buff_left_time(3);
    gameData.updateBuff(buff);
    auto preparation = gameData.buffTimedData().value("terrainPrewarn").toMap();
    QCOMPARE(preparation.value("leftTime").toInt(), 3);

    gameData.setMatchProfile(RM::MatchProfile::Rmul3v3);
    QVERIFY(gameData.territoryStatus().isEmpty());
    gameData.updateGlobalSpecialMechanism(progress);
    QVERIFY(gameData.territoryStatus().isEmpty());
  }

  void test2027PositionPresenceAndRadarUnits() {
    for (const auto profile : {RM::MatchProfile::Rmuc2027,
                               RM::MatchProfile::Rmul3v3,
                               RM::MatchProfile::Rmul1v1}) {
      GameData gameData;
      gameData.setMatchProfile(profile);
      gameData.setCurrentRobotId(103);

      robomaster::RobotPosition position;
      position.set_x(0.0f);
      gameData.updateRobotPosition(position);
      QVERIFY(gameData.getMiniMapMarkers().isEmpty());

      position.set_y(0.0f);
      position.set_yaw(0.0f);
      gameData.updateRobotPosition(position);
      QCOMPARE(gameData.getMiniMapMarkers().size(), 1);
      const auto origin = gameData.getMiniMapMarkers().first().toMap();
      QCOMPARE(origin.value("robotId").toInt(), 103);
      QCOMPARE(origin.value("posX").toDouble(), 0.0);
      QCOMPARE(origin.value("posY").toDouble(), 1.0);
      QVERIFY(origin.value("headingKnown").toBool());

      position.set_x(gameData.fieldWidth() + 1.0);
      gameData.updateRobotPosition(position);
      QCOMPARE(gameData.getRobotById(103)->posX, 0.0f);

      robomaster::RadarInfoToClient radar;
      for (int i = 0; i < 8; ++i)
        radar.add_robot_info();
      // Blue POV still uses the same world frame. Slot 1 is red 3; slot 5 is blue 3.
      radar.mutable_robot_info(1)->set_target_pos_x(125);
      radar.mutable_robot_info(1)->set_target_pos_y(375);
      radar.mutable_robot_info(5)->set_target_pos_x(250);
      radar.mutable_robot_info(5)->set_target_pos_y(125);
      gameData.updateRadarInfo(radar);
      QCOMPARE(gameData.getRobotById(3)->posX, 1.25f);
      QCOMPARE(gameData.getRobotById(3)->posY, 3.75f);
      QCOMPARE(gameData.getRobotById(103)->posX, 2.5f);
      QCOMPARE(gameData.getRobotById(103)->posY, 1.25f);
      QVERIFY(!gameData.getRobotById(3)->hasPositionHeading);
      QCOMPARE(gameData.getMiniMapMarkers().size(), 2);
    }
  }

  void test2027HeavyInstallation() {
    GameData game;
    game.setMatchProfile(RM::MatchProfile::Rmuc2027);
    game.setCurrentRobotId(1);
    robomaster::GameStatus status;
    status.set_current_stage(static_cast<int>(GameStage::BATTLE));
    status.set_current_round(1);
    status.set_stage_countdown_sec(98);
    game.updateGameStatus(status);

    auto heavyCard = [&](bool blue) {
      const auto robots = game.dashboardData().value(blue ? "blueRobots" : "redRobots").toList();
      for (const auto &entry : robots) {
        const auto card = entry.toMap();
        if (card.value("number").toInt() == 1)
          return card;
      }
      return QVariantMap{};
    };
    auto heavy = [&](bool blue) { return heavyCard(blue).value("heavy").toMap(); };
    robomaster::RobotModuleStatus modules;
    modules.set_laser_detection_module(0);
    game.updateRobotModuleStatus(modules);
    QVERIFY(heavy(false).contains("allowed"));
    QVERIFY(!heavy(false).value("allowed").toBool());
    QVERIFY(!heavyCard(true).contains("heavy"));

    modules.set_laser_detection_module(1);
    game.updateRobotModuleStatus(modules);
    QVERIFY(heavy(false).value("allowed").toBool());
    QCOMPARE(game.getMyRobot().value("heavy").toMap(), heavy(false));
    modules.set_laser_detection_module(2);
    game.updateRobotModuleStatus(modules);
    QVERIFY(heavy(false).value("allowed").toBool());

    robomaster::RoboMasterMessage wrapper;
    auto *event = wrapper.mutable_event();
    event->set_event_id(16);
    QSignalSpy popup(&game, &GameData::officialEventPopupRequested);
    game.processProtocolData(wrapper);
    QCOMPARE(popup.count(), 0);
    QVERIFY(!heavy(false).contains("installedAt"));
    event->set_param("101");
    game.processProtocolData(wrapper);
    QCOMPARE(popup.count(), 0);
    QVERIFY(!heavyCard(true).contains("heavy"));
    QVERIFY(!heavy(false).contains("installedAt"));
    event->set_param("1");
    game.processProtocolData(wrapper);
    QCOMPARE(popup.count(), 1);
    const auto installedAt = heavy(false).value("installedAt").toLongLong();
    QVERIFY(installedAt > 0);
    QTest::qWait(15);
    game.processProtocolData(wrapper);
    QCOMPARE(heavy(false).value("installedAt").toLongLong(), installedAt);

    game.setCurrentRobotId(103);
    modules.set_laser_detection_module(0);
    game.updateRobotModuleStatus(modules);
    QVERIFY(!heavyCard(false).contains("heavy"));
    QVERIFY(!heavy(true).contains("installedAt"));
    event->set_param("101");
    game.processProtocolData(wrapper);
    QVERIFY(heavy(true).value("installedAt").toLongLong() > 0);
    status.set_current_round(2);
    game.updateGameStatus(status);
    QVERIFY(heavy(false).isEmpty());
    QVERIFY(heavy(true).isEmpty());
  }

  void test2027HeavyOnOtherSeats() {
    GameData game;
    game.setMatchProfile(RM::MatchProfile::Rmuc2027);
    game.setCurrentRobotId(3);
    auto heavy = [&](bool blue) {
      const auto robots = game.dashboardData().value(blue ? "blueRobots" : "redRobots").toList();
      return robots.first().toMap().value("heavy").toMap();
    };
    robomaster::GameStatus clock;
    clock.set_current_stage(static_cast<int>(GameStage::BATTLE));
    clock.set_current_round(1);
    auto tick = [&](int elapsed) {
      clock.set_stage_elapsed_sec(elapsed);
      clock.set_stage_countdown_sec(420 - elapsed);
      game.updateGameStatus(clock);
    };
    tick(150);
    robomaster::GlobalUnitStatus units;
    units.set_base_health(8500);
    units.set_enemy_base_health(10000);
    game.updateGlobalUnitStatus(units);
    units.set_base_health(9900);
    units.set_total_cp_ally(249);
    units.set_total_cp_enemy(400);
    game.updateGlobalUnitStatus(units);
    tick(169);
    QVERIFY(!heavy(false).value("allowed").toBool());
    tick(170);
    QVERIFY(heavy(false).value("allowed").toBool());
    QVERIFY(!heavy(true).value("allowed").toBool());
    QVERIFY(!heavy(false).contains("installedAt"));

    clock.set_current_round(2);
    tick(120);
    QVERIFY(!heavy(false).value("allowed").toBool());
    robomaster::GlobalLogisticsStatus logistics;
    logistics.set_tech_level(3);
    game.updateGlobalLogisticsStatus(logistics);
    QVERIFY(heavy(false).value("allowed").toBool());
    QVERIFY(!heavy(true).value("allowed").toBool());
    robomaster::RobotStaticStatus staticStatus;
    staticStatus.set_robot_id(1);
    staticStatus.set_connection_state(1);
    staticStatus.set_max_health(600);
    game.updateRobotStaticStatus(staticStatus);
    QVERIFY(!heavy(false).contains("installedAt"));
    robomaster::RobotDynamicStatus counted;
    counted.set_total_projectiles_fired(1);
    game.updateRobotDynamicStatus(counted);
    QVERIFY(!heavy(false).contains("installedAt"));
    game.setCurrentRobotId(1);
    counted.set_total_projectiles_fired(0);
    game.updateRobotDynamicStatus(counted);
    counted.set_total_projectiles_fired(1);
    game.updateRobotDynamicStatus(counted);
    const qint64 first = heavy(false).value("installedAt").toLongLong();
    QVERIFY(first > QDateTime::currentMSecsSinceEpoch() - 1000);
    counted.set_total_projectiles_fired(2);
    game.updateRobotDynamicStatus(counted);
    QCOMPARE(heavy(false).value("installedAt").toLongLong(), first);

    game.setMatchProfile(RM::MatchProfile::Rmul3v3);
    game.setCurrentRobotId(103);
    tick(18);
    staticStatus.set_robot_id(101);
    staticStatus.set_max_health(100);
    game.updateRobotStaticStatus(staticStatus);
    QVERIFY(heavy(true).value("allowed").toBool());
    QVERIFY(!heavy(true).contains("installedAt"));
    staticStatus.set_max_health(450);
    game.updateRobotStaticStatus(staticStatus);
    QVERIFY(heavy(true).value("installedAt").toLongLong() > 0);
  }

  void test2027TeamHeavyStatusOverLoopback() {
    QUdpSocket portReservation;
    QVERIFY(portReservation.bind(QHostAddress(QHostAddress::LocalHost), quint16(0)));
    const QByteArray endpoint = QByteArray("127.0.0.1:") + QByteArray::number(portReservation.localPort());
    portReservation.close();
    const auto original = qgetenv("RM_HEAVY_SYNC_SOURCE");
    qputenv("RM_HEAVY_SYNC_SOURCE", endpoint);
    const auto restore = qScopeGuard([&] {
      if (original.isNull())
        qunsetenv("RM_HEAVY_SYNC_SOURCE");
      else
        qputenv("RM_HEAVY_SYNC_SOURCE", original);
    });

    GameData heavy;
    GameData infantry;
    GameData opposite;
    robomaster::GameStatus status;
    status.set_current_stage(static_cast<int>(GameStage::BATTLE));
    status.set_current_round(1);
    status.set_stage_countdown_sec(240);
    status.set_stage_elapsed_sec(180);
    for (auto *game : {&heavy, &infantry, &opposite}) {
      game->setMatchProfile(RM::MatchProfile::Rmuc2027);
      game->updateGameStatus(status);
    }
    heavy.setCurrentRobotId(1);
    infantry.setCurrentRobotId(3);
    opposite.setCurrentRobotId(103);
    RM::NetworkManager source(&heavy);
    RM::NetworkManager listener(&infantry);
    RM::NetworkManager otherTeam(&opposite);

    auto redState = [](const GameData &game) {
      return game.dashboardData().value("redRobots").toList().first().toMap().value("heavy").toMap();
    };
    robomaster::RobotModuleStatus modules;
    modules.set_laser_detection_module(1);
    heavy.updateRobotModuleStatus(modules);
    QTRY_VERIFY_WITH_TIMEOUT(redState(infantry).value("allowed").toBool(), 1600);
    QVERIFY(!redState(opposite).value("allowed").toBool());

    robomaster::RobotDynamicStatus telemetry;
    heavy.updateRobotDynamicStatus(telemetry);
    telemetry.set_total_projectiles_fired(1);
    heavy.updateRobotDynamicStatus(telemetry);
    QTRY_VERIFY_WITH_TIMEOUT(redState(infantry).value("installedAt").toLongLong() > 0, 1600);
    QVERIFY(!redState(opposite).contains("installedAt"));

    // The first subscriber joins after the fan-out, and avoids replaying an old transition.
    auto completed = heavy.teamHeavyStatus();
    completed["installation_age_ms"] = 1000;
    GameData late;
    late.setMatchProfile(RM::MatchProfile::Rmuc2027);
    late.setCurrentRobotId(4);
    late.updateGameStatus(status);
    late.updateTeamHeavyStatus(completed);
    QVERIFY(redState(late).value("installedAt").toLongLong()
            <= QDateTime::currentMSecsSinceEpoch() - 1000);
    QVERIFY(redState(late).contains("installedAt"));
    status.set_current_round(2);
    late.updateGameStatus(status);
    late.updateTeamHeavyStatus(completed);
    QVERIFY(!redState(late).contains("installedAt"));
    QVERIFY(!redState(late).value("allowed").toBool());
  }

  void test2027ProfileMapAndSettlement() {
    Q_INIT_RESOURCE(resources);
    GameData gameData;
    for (auto profile : {RM::MatchProfile::Rmuc2027,
                         RM::MatchProfile::Rmul3v3, RM::MatchProfile::Rmul1v1}) {
      gameData.setMatchProfile(profile);
      gameData.setCurrentRobotId(3);
      robomaster::RobotPosition position;
      position.set_x(0.5f);
      position.set_y(gameData.fieldHeight() / 2);
      gameData.updateRobotPosition(position);
      const QVariantList markers = gameData.getMiniMapMarkers();
      QCOMPARE(markers.size(), 1);
      const auto marker = markers.first().toMap();
      QCOMPARE(marker.value("posX").toDouble(), 0.5 / gameData.fieldWidth());
      QCOMPARE(marker.value("posY").toDouble(), 0.5);
      const QString mapPath = gameData.mapBackground().mid(3);
      QVERIFY(mapPath.endsWith(QStringLiteral(".png")));
      const QSize pixels = QImageReader(mapPath).size();
      QVERIFY(pixels.isValid());
      QCOMPARE(pixels.width() * gameData.fieldHeight(),
               pixels.height() * gameData.fieldWidth());
    }
    QCOMPARE(gameData.fieldWidth(), 5.0);
    QCOMPARE(gameData.fieldHeight(), 5.0);
    QCOMPARE(gameData.getGameTime(), 120);
    QVERIFY(!gameData.hasBases());
    QCOMPARE(gameData.getAllRobots().size(), 2);

    robomaster::GameStatus result;
    result.set_current_stage(static_cast<int>(GameStage::SETTLEMENT));
    result.set_red_score(9);
    result.set_blue_score(1);
    result.set_game_result(2);
    result.set_end_reason(2);
    result.set_stage_elapsed_sec(120);
    gameData.updateGameStatus(result);
    QCOMPARE(gameData.determineWinner(), 2);
    QCOMPARE(gameData.getFormattedStageElapsedTime(), QString("02:00"));
    QVERIFY(!gameData.settlementReason().isEmpty());
  }

  void testRobotRosterRequiresStaticStatus() {
    GameData gameData;

    robomaster::GlobalUnitStatusInternal unitStatus;
    unitStatus.add_red_robot_health(4000);
    unitStatus.add_red_robot_health(500);
    unitStatus.add_red_robot_health(400);
    unitStatus.add_red_robot_health(400);
    unitStatus.add_red_robot_health(300);
    unitStatus.add_red_robot_health(600);
    gameData.updateGlobalUnitStatusInternal(unitStatus);

    QVariantMap robot3 = gameData.getRobotInfo(3);
    QCOMPARE(robot3.value("hp").toInt(), 400);
    QVERIFY(robot3.value("isOffline").toBool());
    QVERIFY(!robot3.value("isClientConnected").toBool());

    robomaster::RobotStaticStatus staticStatus;
    staticStatus.set_robot_id(3);
    staticStatus.set_connection_state(2);
    staticStatus.set_field_state(0);
    staticStatus.set_alive_state(1);
    staticStatus.set_level(2);
    staticStatus.set_max_health(400);
    gameData.updateRobotStaticStatus(staticStatus);

    robot3 = gameData.getRobotInfo(3);
    QVERIFY(!robot3.value("isOffline").toBool());
    QVERIFY(robot3.value("isClientConnected").toBool());

    staticStatus.set_robot_id(6);
    staticStatus.set_connection_state(0);
    staticStatus.set_field_state(0);
    staticStatus.set_alive_state(1);
    staticStatus.set_max_health(300);
    gameData.updateRobotStaticStatus(staticStatus);

    QVariantMap robot6 = gameData.getRobotInfo(6);
    QVERIFY(!robot6.value("isOffline").toBool());
    QVERIFY(!robot6.value("isClientConnected").toBool());

    staticStatus.set_field_state(1);
    gameData.updateRobotStaticStatus(staticStatus);

    robot6 = gameData.getRobotInfo(6);
    QVERIFY(robot6.value("isOffline").toBool());
  }

  void testFreeRespawnCompletionOverridesStaleProgress() {
    GameData gameData;

    QVariantMap reading;
    reading.insert(QStringLiteral("is_pending_respawn"), true);
    reading.insert(QStringLiteral("total_respawn_progress"), 47u);
    reading.insert(QStringLiteral("current_respawn_progress"), 46u);
    reading.insert(QStringLiteral("can_free_respawn"), false);
    gameData.processRobotRespawnStatusMap(reading);

    QVariantMap completed;
    completed.insert(QStringLiteral("is_pending_respawn"), true);
    completed.insert(QStringLiteral("total_respawn_progress"), 0u);
    completed.insert(QStringLiteral("current_respawn_progress"), 0u);
    completed.insert(QStringLiteral("can_free_respawn"), true);
    gameData.processRobotRespawnStatusMap(completed);

    const QVariantMap status = gameData.robotRespawnStatus();
    QVERIFY(status.value(QStringLiteral("can_free_respawn")).toBool());
    QCOMPARE(status.value(QStringLiteral("total_respawn_progress")).toUInt(),
             47u);
    QCOMPARE(status.value(QStringLiteral("current_respawn_progress")).toUInt(),
             47u);
  }

  /**
   * @brief 测试基地数据更新
   * 验证基地血量更新逻辑。
   */
  void testUpdateBaseData() {
    GameData gameData;

    QSignalSpy spy(&gameData, &GameData::baseHealthUpdated);

    // 使用新的辅助接口
    gameData.updateBaseHP(TeamColor::RED, 4500);
    gameData.updateBaseStatus(TeamColor::RED, 0); // 0 表示无敌

    QCOMPARE(spy.count(), 1);

    const BaseData &redBase = gameData.getRedBase();
    QCOMPARE(redBase.currentHP, 4500);
    QVERIFY(redBase.isInvincible);
  }

  void testAllyBaseHealthDropAlertTriggersAfterOneSecondWindow() {
    GameData gameData;
    gameData.setCurrentRobotId(1);

    QSignalSpy spy(&gameData, &GameData::allyBaseHealthDropAlertTriggered);

    gameData.updateBaseHP(TeamColor::RED, 5000);
    QTest::qWait(1100);
    gameData.updateBaseHP(TeamColor::RED, 4980);

    QCOMPARE(spy.count(), 1);
  }

  /**
   * @brief 测试比赛状态更新
   * 验证比赛阶段和时间的更新。
   */
  void testUpdateGameState() {
    GameData gameData;

    robomaster::GameInfo gameInfo;
    gameInfo.set_stage(
        robomaster::GameStage::STAGE_BATTLE); // 在 GameData 中映射为 BATTLE（4）
    gameInfo.set_time_remaining(300);

    QSignalSpy spy(&gameData, &GameData::gameStateUpdated);

    gameData.updateGameState(gameInfo);

    QCOMPARE(spy.count(), 1);
    QCOMPARE(gameData.getCurrentStage(), GameStage::BATTLE);
    QCOMPARE(gameData.getGameTime(), 300);
  }

  void testDetermineWinnerUsesBattleToSettlementScoreDelta() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(2);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_red_score(3);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.redRoundScoreDelta(), 1);
    QCOMPARE(gameData.blueRoundScoreDelta(), 0);
    QCOMPARE(gameData.determineWinner(), quint8(1));
  }

  void testDetermineWinnerIgnoresAbsoluteScoreLead() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(4);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_red_score(4);
    status.set_blue_score(2);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.redRoundScoreDelta(), 0);
    QCOMPARE(gameData.blueRoundScoreDelta(), 1);
    QCOMPARE(gameData.determineWinner(), quint8(2));
  }

  void testDetermineWinnerDrawsWhenScoreDeltaEqual() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(2);
    status.set_blue_score(2);
    gameData.updateGameStatus(status);

    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_red_score(3);
    status.set_blue_score(3);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.determineWinner(), quint8(0));
  }

  void testDetermineWinnerFallbackToAbsoluteScoreWhenBaselineMissing() {
    GameData gameData;
    // 从未进入 BATTLE 阶段，基线未设置
    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_current_round(1);
    status.set_red_score(5);
    status.set_blue_score(3);
    gameData.updateGameStatus(status);

    // 基线丢失时应回退到绝对分数判定：红方 5 > 蓝方 3
    QCOMPARE(gameData.determineWinner(), quint8(1));
  }

  void testDetermineWinnerFallbackDrawWhenBaselineMissingAndScoreEqual() {
    GameData gameData;
    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_current_round(1);
    status.set_red_score(3);
    status.set_blue_score(3);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.determineWinner(), quint8(0));
  }

  void testBaselinePreservedInSettlementOnRoundChange() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(2);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    // 进入结算阶段，同时回合数增加（模拟引擎结算时发送 round+1）
    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_current_round(2);
    status.set_red_score(3);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    // 基线应保留，增量为 1:0，红方胜
    QCOMPARE(gameData.determineWinner(), quint8(1));
  }

  void testProcessGameResultEmitsScoreDeltaWinner() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(1);
    status.set_blue_score(1);
    gameData.updateGameStatus(status);

    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_red_score(1);
    status.set_blue_score(2);
    gameData.updateGameStatus(status);

    QSignalSpy resultSpy(&gameData, &GameData::gameResultReceived);
    gameData.processGameResult(0);

    QCOMPARE(resultSpy.count(), 1);
    QCOMPARE(resultSpy.takeFirst().at(0).toUInt(), uint(2));
  }

  void testGameResultEventDoesNotPreemptSettlementScoreSnapshot() {
    GameData gameData;

    robomaster::GameStatus status;
    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(300);
    status.set_current_round(1);
    status.set_red_score(0);
    status.set_blue_score(0);
    gameData.updateGameStatus(status);

    QSignalSpy resultSpy(&gameData, &GameData::gameResultReceived);
    gameData.processGameResult(0);

    QCOMPARE(resultSpy.count(), 0);
    QCOMPARE(gameData.getCurrentStage(), GameStage::BATTLE);

    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    status.set_red_score(1);
    status.set_blue_score(0);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.redRoundScoreDelta(), 1);
    QCOMPARE(gameData.blueRoundScoreDelta(), 0);
    QCOMPARE(gameData.determineWinner(), quint8(1));
  }

  void testGlobalSpecialMechanismTriggersAlertOnceAtOneSecond() {
    GameData gameData;
    QSignalSpy alertSpy(&gameData, &GameData::allyFortressOccupationAlertTriggered);

    robomaster::GlobalSpecialMechanism twoSecondMsg;
    twoSecondMsg.add_mechanism_id(1);
    twoSecondMsg.add_mechanism_time_sec(2);
    gameData.updateGlobalSpecialMechanism(twoSecondMsg);

    QCOMPARE(gameData.allyFortressOccupationSec(), 2);
    QCOMPARE(gameData.enemyFortressOccupationSec(), 0);
    QCOMPARE(alertSpy.count(), 0);

    robomaster::GlobalSpecialMechanism oneSecondMsg;
    oneSecondMsg.add_mechanism_id(1);
    oneSecondMsg.add_mechanism_time_sec(1);
    gameData.updateGlobalSpecialMechanism(oneSecondMsg);

    QCOMPARE(gameData.allyFortressOccupationSec(), 1);
    QCOMPARE(alertSpy.count(), 1);

    gameData.updateGlobalSpecialMechanism(oneSecondMsg);
    QCOMPARE(alertSpy.count(), 1);

    robomaster::GlobalSpecialMechanism resetMsg;
    gameData.updateGlobalSpecialMechanism(resetMsg);
    QCOMPARE(gameData.allyFortressOccupationSec(), 0);
    QCOMPARE(alertSpy.count(), 1);
  }

  void testAllyOutpostHealthDropAlertOnlyTracksOwnSide() {
    GameData gameData;
    QSignalSpy alertSpy(&gameData, &GameData::allyOutpostHealthDropAlertTriggered);

    gameData.updateOutpostHP(TeamColor::RED, 1500);
    QTest::qWait(5100);

    gameData.updateOutpostHP(TeamColor::BLUE, 1000);
    QCOMPARE(alertSpy.count(), 0);

    // A：5 秒内正好掉 200 血，作为首次有效提示发出。
    gameData.updateOutpostHP(TeamColor::RED, 1300);
    QCOMPARE(alertSpy.count(), 1);

    // B：又过 5 秒再掉 300 血，但 B-A < 15s，丢弃 B 且不更新 A。
    QTest::qWait(5100);
    gameData.updateOutpostHP(TeamColor::RED, 1000);
    QCOMPARE(alertSpy.count(), 1);

    // 维持一个新的 5 秒窗口基线。
    QTest::qWait(5100);
    gameData.updateOutpostHP(TeamColor::RED, 1000);
    QCOMPARE(alertSpy.count(), 1);

    // C：距 A 已超过 15s，5 秒内正好掉 200 血，应再次发出。
    QTest::qWait(5100);
    gameData.updateOutpostHP(TeamColor::RED, 800);
    QCOMPARE(alertSpy.count(), 2);
  }

  void testEnemyOutpostHealthTracksCurrentRobotPerspective() {
    GameData gameData;
    gameData.updateOutpostHP(TeamColor::RED, 900);
    gameData.updateOutpostHP(TeamColor::BLUE, 300);

    gameData.setCurrentRobotId(1);
    QCOMPARE(gameData.enemyOutpostHealth(), 300);

    gameData.setCurrentRobotId(101);
    QCOMPARE(gameData.enemyOutpostHealth(), 900);
  }

  void testAllyBaseHealthDropAlertOnlyTracksOwnSide() {
    GameData gameData;
    QSignalSpy alertSpy(&gameData, &GameData::allyBaseHealthDropAlertTriggered);

    gameData.updateBaseHP(TeamColor::RED, 5000);
    QTest::qWait(1010);

    gameData.updateBaseHP(TeamColor::BLUE, 4980);
    QCOMPARE(alertSpy.count(), 0);

    gameData.updateBaseHP(TeamColor::RED, 4980);
    QCOMPARE(alertSpy.count(), 1);

    gameData.updateBaseHP(TeamColor::RED, 4970);
    QCOMPARE(alertSpy.count(), 1);
  }

  /**
   * @brief 测试无效机器人ID
   */
  void testInvalidRobotId() {
    GameData gameData;
    const RobotData *robot = gameData.getRobotById(99); // 不存在的ID
    QVERIFY(robot == nullptr);
  }

  /**
   * @brief 测试边界条件
   */
  void testBoundaryConditions() {
    GameData gameData;
    robomaster::RobotStatus statusMsg;
    statusMsg.set_id(1);

    // 测试 0 血量
    statusMsg.set_hp(0);
    gameData.updateRobotData(statusMsg);
    const RobotData *robot = gameData.getRobotById(1);
    QCOMPARE(robot->currentHP, 0);

    // 测试超大血量 (虽然逻辑上不应该发生，但验证是否正确存储)
    statusMsg.set_hp(65535);
    gameData.updateRobotData(statusMsg);
    QCOMPARE(robot->currentHP, 65535);
  }

  void testRadarInfoUsesEnemyThenAllyOrder() {
    GameData gameData;
    gameData.setCurrentRobotId(1);

    robomaster::RadarInfoToClient packetFromRedPerspective;
    for (int i = 0; i < 12; ++i) {
      auto *info = packetFromRedPerspective.add_robot_info();
      info->set_target_pos_x(static_cast<uint32_t>((i + 1) * 100));
      info->set_target_pos_y(static_cast<uint32_t>((i + 1) * 200));
      info->set_is_high_light(i % 2);
    }

    gameData.updateRadarInfo(packetFromRedPerspective);

    const RobotData *redHero = gameData.getRobotById(1);
    const RobotData *redSentry = gameData.getRobotById(7);
    const RobotData *blueHero = gameData.getRobotById(101);
    const RobotData *blueSentry = gameData.getRobotById(107);
    QVERIFY(redHero != nullptr);
    QVERIFY(redSentry != nullptr);
    QVERIFY(blueHero != nullptr);
    QVERIFY(blueSentry != nullptr);

    // V2.0.0 固定按对方 1/2/3/4/6/7、己方 1/2/3/4/6/7 排列。
    QCOMPARE(redHero->posX, 7.0f);
    QCOMPARE(redHero->posY, 14.0f);
    QCOMPARE(redHero->isHighLight, quint8(0));
    QCOMPARE(redSentry->posX, 12.0f);
    QCOMPARE(redSentry->posY, 24.0f);
    QCOMPARE(redSentry->isHighLight, quint8(1));
    QCOMPARE(blueHero->posX, 1.0f);
    QCOMPARE(blueHero->posY, 2.0f);
    QCOMPARE(blueHero->isHighLight, quint8(0));
    QCOMPARE(blueSentry->posX, 6.0f);
    QCOMPARE(blueSentry->posY, 12.0f);
    QCOMPARE(blueSentry->isHighLight, quint8(1));

    gameData.setCurrentRobotId(101);
    robomaster::RadarInfoToClient packetFromBluePerspective;
    for (int i = 0; i < 12; ++i) {
      auto *info = packetFromBluePerspective.add_robot_info();
      info->set_target_pos_x(static_cast<uint32_t>((i + 1) * 150));
      info->set_target_pos_y(static_cast<uint32_t>((i + 1) * 250));
      info->set_is_high_light((i + 1) % 2);
    }

    gameData.updateRadarInfo(packetFromBluePerspective);

    QCOMPARE(redHero->posX, 1.5f);
    QCOMPARE(redHero->posY, 2.5f);
    QCOMPARE(redHero->isHighLight, quint8(1));
    QCOMPARE(redSentry->posX, 9.0f);
    QCOMPARE(redSentry->posY, 15.0f);
    QCOMPARE(redSentry->isHighLight, quint8(0));
    QCOMPARE(blueHero->posX, 10.5f);
    QCOMPARE(blueHero->posY, 17.5f);
    QCOMPARE(blueHero->isHighLight, quint8(1));
    QCOMPARE(blueSentry->posX, 18.0f);
    QCOMPARE(blueSentry->posY, 30.0f);
    QCOMPARE(blueSentry->isHighLight, quint8(0));
  }

  /**
   * @brief 测试伤害记录
   */
  void testDamageRecord() {
    GameData gameData;
    robomaster::RobotStatus victimStatus;
    victimStatus.set_id(101);
    victimStatus.set_hp(200);
    victimStatus.set_max_hp(200);
    gameData.updateRobotData(victimStatus);

    DamageEventData damageData;
    damageData.attackerId = 1;
    damageData.victimId = 101;
    damageData.damage = 50;
    damageData.armorId = 1;
    damageData.hurtType = 0;

    gameData.recordDamageEvent(damageData);

    // 验证伤害历史
    QCOMPARE(gameData.getDamageHistory().size(), 1);
    QCOMPARE(gameData.getDamageHistory().first().damage, 50);

    // 受击事件只记录伤害历史和刷新信号，权威 HP 仍由 RobotStatus /
    // GlobalUnitStatus 等状态包驱动，不能在这里本地扣血。
    const RobotData *victim = gameData.getRobotById(101);
    QVERIFY(victim != nullptr);
    QCOMPARE(victim->currentHP, 200);
    QCOMPARE(victim->maxHP, 200);
  }

  void testOverPowerPenaltyUpdatesChassisStatus() {
    GameData gameData;
    gameData.setMyRobotId(1);

    QSignalSpy myRobotSpy(&gameData, &GameData::myRobotUpdated);

    robomaster::PenaltyInfo penalty;
    penalty.set_penalty_type(4);
    penalty.set_penalty_effect_sec(10);
    penalty.set_total_penalty_num(1);
    gameData.updatePenalty(penalty);

    QCOMPARE(gameData.chassisStatus(), QStringLiteral("超限断电 10s"));
    QVERIFY(myRobotSpy.count() >= 1);

    const int signalCountAfterFirstUpdate = myRobotSpy.count();
    penalty.set_penalty_effect_sec(7);
    gameData.updatePenalty(penalty);

    QCOMPARE(gameData.chassisStatus(), QStringLiteral("超限断电 7s"));
    QVERIFY(myRobotSpy.count() > signalCountAfterFirstUpdate);

    penalty.set_penalty_effect_sec(0);
    gameData.updatePenalty(penalty);

    QCOMPARE(gameData.chassisStatus(), QString());
  }

  void testHeroFrameSourceUpdatesForQmlImageProvider() {
    GameData gameData;
    QSignalSpy spy(&gameData, &GameData::heroFrameUpdated);

    QVERIFY(!gameData.hasHeroFrame());
    QCOMPARE(gameData.heroFrameRevision(), quint64(0));
    QVERIFY(gameData.heroFrameSource().isEmpty());

    QImage frame(8, 6, QImage::Format_RGB32);
    frame.fill(Qt::red);
    gameData.onVideoFrameReceived(frame);

    QVERIFY(gameData.hasHeroFrame());
    QCOMPARE(gameData.heroFrame().size(), QSize(8, 6));
    QCOMPARE(gameData.heroFrameRevision(), quint64(1));
    QVERIFY(gameData.heroFrameSource().startsWith(
        QStringLiteral("image://herovideo/frame?rev=1")));
    QCOMPARE(spy.count(), 1);

    gameData.clearHeroFrame();

    QVERIFY(!gameData.hasHeroFrame());
    QCOMPARE(gameData.heroFrameRevision(), quint64(2));
    QVERIFY(gameData.heroFrameSource().isEmpty());
    QCOMPARE(spy.count(), 2);
  }

  void testDartHitOcclusionDurationFollowsFixedTargetHitCount() {
    GameData gameData;

    gameData.simulateDartHit(1, 1);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit1);

    gameData.simulateDartHit(1, 2);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit2);

    gameData.simulateDartHit(1, 3);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit3);

    gameData.simulateDartHit(1, 1);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit4);
  }

  void testOfficialTechCoreStatusAndRemoteExchangePermission() {
    GameData gameData;

    robomaster::TechCoreMotionStateSync techCore;
    techCore.set_maximum_difficulty_level(4);
    techCore.set_basic_state(3);
    techCore.set_putin_state(1);
    techCore.set_move_state(1);
    techCore.set_rotate_state(0);
    techCore.set_enemy_core_status(2);
    techCore.set_remain_time_all(45);
    techCore.set_remain_time_step(5);

    QSignalSpy techCoreSpy(&gameData,
                           &GameData::techCoreMotionStateSyncUpdated);
    gameData.updateTechCoreMotionStateSync(techCore);

    QCOMPARE(techCoreSpy.count(), 1);
    QCOMPARE(gameData.maximumDifficultyLevel(), 4u);
    QCOMPARE(gameData.techCoreBasicState(), 3u);
    QCOMPARE(gameData.techCorePutinState(), 1u);
    QCOMPARE(gameData.techCoreMoveState(), 1u);
    QCOMPARE(gameData.techCoreRotateState(), 0u);
    QCOMPARE(gameData.enemyStatus(), 2u);
    QCOMPARE(gameData.remainTimeAll(), 45u);
    QCOMPARE(gameData.remainTimeStep(), 5u);

    robomaster::RoboMasterMessage eventWrapper;
    eventWrapper.mutable_event()->set_event_id(15);
    eventWrapper.mutable_event()->set_param("0");
    gameData.processProtocolData(eventWrapper);

    // Event 15 是飞镖闸门开启，不得修改 V2.0.0 工程装配同步状态。
    QCOMPARE(gameData.techCoreBasicState(), 3u);
    QCOMPARE(gameData.techCorePutinState(), 1u);
    QCOMPARE(gameData.techCoreMoveState(), 1u);
    QCOMPARE(gameData.techCoreRotateState(), 0u);
    QCOMPARE(gameData.enemyStatus(), 2u);

    eventWrapper.mutable_event()->set_event_id(14);
    eventWrapper.mutable_event()->set_param("1");
    gameData.processProtocolData(eventWrapper);

    // Event 14 是飞镖命中，也不得修改 V2.0.0 工程装配同步状态。
    QCOMPARE(gameData.techCoreBasicState(), 3u);
    QCOMPARE(gameData.techCorePutinState(), 1u);
    QCOMPARE(gameData.techCoreMoveState(), 1u);
    QCOMPARE(gameData.techCoreRotateState(), 0u);
    QCOMPARE(gameData.enemyStatus(), 2u);

    gameData.setMyRobotId(3);
    robomaster::RobotDynamicStatus dynamicStatus;
    dynamicStatus.set_is_out_of_combat(false);
    dynamicStatus.set_can_remote_heal(false);
    dynamicStatus.set_can_remote_ammo(true);
    gameData.updateRobotDynamicStatus(dynamicStatus);

    QVERIFY(gameData.canRemoteAmmo());
    QVERIFY(gameData.canRemoteExchange());
  }

  void testDartHitOcclusionDurationForMovingTargetsIsAlwaysTenSeconds() {
    GameData gameData;

    gameData.simulateDartHit(1, 1);
    gameData.simulateDartHit(1, 2);
    gameData.simulateDartHit(1, 3);

    gameData.simulateDartHit(1, 4);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionMovingTarget);

    gameData.simulateDartHit(1, 5);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionMovingTarget);
  }

  void testDartHitCountersResetWhenBattleReenters() {
    GameData gameData;

    gameData.simulateDartHit(1, 1);
    gameData.simulateDartHit(1, 2);
    QCOMPARE(gameData.redDartHits(), 2);

    robomaster::GameStatus status;
    status.set_current_round(1);
    status.set_current_stage(robomaster::GameStage::STAGE_PREPARATION);
    status.set_stage_countdown_sec(20);
    gameData.updateGameStatus(status);

    status.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    status.set_stage_countdown_sec(420);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.redDartHits(), 0);
    QCOMPARE(gameData.blueDartHits(), 0);

    gameData.simulateDartHit(1, 1);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit1);
  }

  void testDartHitCountersResetWhenEnteringSettlement() {
    GameData gameData;

    gameData.simulateDartHit(1, 1);
    gameData.simulateDartHit(1, 2);
    gameData.simulateDartHit(1, 3);
    QCOMPARE(gameData.redDartHits(), 3);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit3);

    robomaster::GameStatus status;
    status.set_current_round(1);
    status.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    status.set_stage_countdown_sec(0);
    gameData.updateGameStatus(status);

    QCOMPARE(gameData.redDartHits(), 0);
    QCOMPARE(gameData.blueDartHits(), 0);

    gameData.simulateDartHit(1, 1);
    QCOMPARE(gameData.redDartHits(), 1);
    QCOMPARE(gameData.dartMessageData().value("occlusionDurationSec").toInt(),
             RM::Dart::kOcclusionFixedHit1);
  }

  void testEvent8AirSupportCounteredEmitsSoundSelector() {
    GameData gameData;
    QSignalSpy soundSpy(&gameData, &GameData::airSupportCountered);
    QSignalSpy systemSpy(&gameData, &GameData::systemMessageReceived);

    robomaster::RoboMasterMessage message;
    auto *event = message.mutable_event();
    event->set_event_id(8);
    event->set_param("2");

    gameData.processProtocolData(message);

    QCOMPARE(soundSpy.count(), 1);
    QCOMPARE(soundSpy.takeFirst().at(0).toString(),
             QStringLiteral("2"));
    QCOMPARE(systemSpy.count(), 1);
    QCOMPARE(systemSpy.takeFirst().at(0).toString(),
             QStringLiteral("7:00 对方空中支援被反制，己方剩余可反制次数 2"));
  }

  void testAirSupportLaserTargetingUsesStateEdges() {
    GameData gameData;
    QSignalSpy targetingSpy(
        &gameData, &GameData::airSupportTargetingStateChanged);
    QSignalSpy statusSpy(&gameData, &GameData::airSupportStatusUpdated);

    robomaster::AirSupportStatusSync status;
    status.set_airsupport_status(1);
    status.set_left_time(30);
    status.set_cost_coins(5);
    status.set_is_being_targeted(1);
    status.set_shooter_status(1);

    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(gameData.airSupportIsBeingTargeted(), 1);
    QCOMPARE(gameData.airSupportShooterStatus(), 1);
    QCOMPARE(targetingSpy.count(), 1);
    QCOMPARE(targetingSpy.at(0).at(0).toBool(), true);
    QCOMPARE(statusSpy.count(), 1);

    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(targetingSpy.count(), 1);
    QCOMPARE(statusSpy.count(), 1);

    status.set_left_time(29);
    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(targetingSpy.count(), 1);
    QCOMPARE(statusSpy.count(), 2);

    status.set_shooter_status(0);
    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(gameData.airSupportShooterStatus(), 0);
    QCOMPARE(targetingSpy.count(), 1);
    QCOMPARE(statusSpy.count(), 3);

    status.set_is_being_targeted(0);
    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(targetingSpy.count(), 2);
    QCOMPARE(targetingSpy.at(1).at(0).toBool(), false);

    status.set_is_being_targeted(2);
    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(gameData.airSupportIsBeingTargeted(), 2);
    QCOMPARE(targetingSpy.count(), 2);

    status.set_is_being_targeted(1);
    gameData.updateAirSupportStatusSync(status);
    QCOMPARE(targetingSpy.count(), 3);
    QCOMPARE(targetingSpy.at(2).at(0).toBool(), true);
  }

  void testAllyBaseArmorOpenedUsesStateEdgesForRedPerspective() {
    GameData gameData;
    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);

    QSignalSpy armorOpenedSpy(
        &gameData, &GameData::allyBaseArmorOpenedTriggered);
    QSignalSpy baseStatusSpy(&gameData, &GameData::baseStatusChanged);

    robomaster::GlobalUnitStatus status;
    status.set_base_health(5000);
    status.set_base_shield(100);
    status.set_base_status(2);

    // 首包只建立基线，即使已经展开也不补播。
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);
    QCOMPARE(gameData.getRedBase().status, static_cast<quint8>(2));
    QCOMPARE(gameData.getRedBase().virtualShield, static_cast<quint16>(100));

    // 周期性重复快照不应重复触发。
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);

    status.set_base_status(1);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);

    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 1);

    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 1);

    status.set_base_status(0);
    gameData.updateGlobalUnitStatus(status);
    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 2);

    // 原有基地状态通知仍按状态变化发送。
    QCOMPARE(baseStatusSpy.count(), 5);
  }

  void testEnemyBaseArmorOpenedDoesNotTriggerAllyVoice() {
    GameData gameData;
    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);

    QSignalSpy armorOpenedSpy(
        &gameData, &GameData::allyBaseArmorOpenedTriggered);

    robomaster::GlobalUnitStatus status;
    status.set_base_health(5000);
    status.set_base_status(1);
    status.set_enemy_base_health(5000);
    status.set_enemy_base_status(1);
    gameData.updateGlobalUnitStatus(status);

    status.set_enemy_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);
    QCOMPARE(gameData.getBlueBase().status, static_cast<quint8>(2));

    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 1);
  }

  void testAllyBaseArmorOpenedUsesBluePerspective() {
    GameData gameData;
    gameData.setCurrentRobotId(101);
    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);

    QSignalSpy armorOpenedSpy(
        &gameData, &GameData::allyBaseArmorOpenedTriggered);

    robomaster::GlobalUnitStatus status;
    status.set_base_health(5000);
    status.set_base_shield(75);
    status.set_base_status(1);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);

    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 1);
    QCOMPARE(gameData.getBlueBase().status, static_cast<quint8>(2));
    QCOMPARE(gameData.getBlueBase().virtualShield, static_cast<quint16>(75));
  }

  void testAllyBaseArmorOpenedIsSuppressedBeforeBattle() {
    GameData gameData;
    QSignalSpy armorOpenedSpy(
        &gameData, &GameData::allyBaseArmorOpenedTriggered);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_PREPARATION);
    gameStatus.set_stage_countdown_sec(0);
    gameData.updateGameStatus(gameStatus);

    robomaster::GlobalUnitStatus status;
    status.set_base_health(5000);
    status.set_base_status(1);
    gameData.updateGlobalUnitStatus(status);
    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);

    // 进入比赛后仍为展开状态时不补播准备阶段事件。
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 0);

    // 比赛中离开状态 2 后再次展开应正常播报。
    status.set_base_status(1);
    gameData.updateGlobalUnitStatus(status);
    status.set_base_status(2);
    gameData.updateGlobalUnitStatus(status);
    QCOMPARE(armorOpenedSpy.count(), 1);
  }

  void testRuneVoicePromptFollowsGameClockAndRuneStatus() {
    GameData gameData;
    QSignalSpy voiceSpy(&gameData, &GameData::runeVoicePromptRequested);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameStatus.set_current_round(1);
    gameData.updateGameStatus(gameStatus);

    robomaster::RuneStatusSync runeStatus;
    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);

    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.count(), 1);
    QCOMPARE(voiceSpy.at(0).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(0).at(1).toInt(), 1);

    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.count(), 1);

    runeStatus.set_rune_status(2);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(360);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.count(), 1);

    gameStatus.set_stage_countdown_sec(330);
    gameData.updateGameStatus(gameStatus);
    runeStatus.set_rune_status(3);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(300);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 2);
    QCOMPARE(voiceSpy.at(1).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(1).at(1).toInt(), 1);
  }

  void testRuneVoicePromptHandlesServerOpeningZeroSequence() {
    GameData gameData;
    QSignalSpy voiceSpy(&gameData, &GameData::runeVoicePromptRequested);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_COUNTDOWN);
    gameStatus.set_stage_countdown_sec(0);
    gameData.updateGameStatus(gameStatus);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameData.updateGameStatus(gameStatus);
    gameData.updateGameStatus(gameStatus);

    robomaster::RuneStatusSync runeStatus;
    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);

    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 1);
    QCOMPARE(voiceSpy.at(0).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(0).at(1).toInt(), 1);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    gameStatus.set_stage_countdown_sec(0);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_current_round(2);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_COUNTDOWN);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameData.updateGameStatus(gameStatus);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 2);
    QCOMPARE(voiceSpy.at(1).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(1).at(1).toInt(), 1);
  }

  void testRuneVoicePromptHandlesServerOpeningOneSequence() {
    GameData gameData;
    QSignalSpy voiceSpy(&gameData, &GameData::runeVoicePromptRequested);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(1);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_COUNTDOWN);
    gameStatus.set_stage_countdown_sec(1);
    gameData.updateGameStatus(gameStatus);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameData.updateGameStatus(gameStatus);
    gameData.updateGameStatus(gameStatus);

    robomaster::RuneStatusSync runeStatus;
    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);

    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 1);
    QCOMPARE(voiceSpy.at(0).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(0).at(1).toInt(), 1);
  }

  void testRuneVoiceSettlementResetsSameRoundSimulation() {
    GameData gameData;
    QSignalSpy voiceSpy(&gameData, &GameData::runeVoicePromptRequested);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_round(0);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_COUNTDOWN);
    gameStatus.set_stage_countdown_sec(1);
    gameData.updateGameStatus(gameStatus);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameData.updateGameStatus(gameStatus);

    robomaster::RuneStatusSync runeStatus;
    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);

    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.count(), 1);
    QCOMPARE(voiceSpy.at(0).at(1).toInt(), 1);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_SETTLEMENT);
    gameStatus.set_stage_countdown_sec(0);
    gameData.updateGameStatus(gameStatus);

    gameStatus.set_current_stage(robomaster::GameStage::STAGE_COUNTDOWN);
    gameStatus.set_stage_countdown_sec(1);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameData.updateGameStatus(gameStatus);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(420);
    gameData.updateGameStatus(gameStatus);
    gameStatus.set_stage_countdown_sec(390);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 2);
    QCOMPARE(voiceSpy.at(1).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(1).at(1).toInt(), 1);
  }

  void testRuneVoiceDirectActivatedStatusReducesPromptCount() {
    GameData gameData;
    QSignalSpy voiceSpy(&gameData, &GameData::runeVoicePromptRequested);

    robomaster::GameStatus gameStatus;
    gameStatus.set_current_stage(robomaster::GameStage::STAGE_BATTLE);
    gameStatus.set_stage_countdown_sec(420);
    gameStatus.set_current_round(1);
    gameData.updateGameStatus(gameStatus);

    robomaster::RuneStatusSync runeStatus;
    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);

    gameStatus.set_stage_countdown_sec(330);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.count(), 1);
    QCOMPARE(voiceSpy.at(0).at(1).toInt(), 2);

    runeStatus.set_rune_status(3);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(300);
    gameData.updateGameStatus(gameStatus);

    QCOMPARE(voiceSpy.count(), 2);
    QCOMPARE(voiceSpy.at(1).at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Small));
    QCOMPARE(voiceSpy.at(1).at(1).toInt(), 1);

    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(240);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.last().at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Large));
    QCOMPARE(voiceSpy.last().at(1).toInt(), 1);

    runeStatus.set_rune_status(3);
    gameData.updateRuneStatusSync(runeStatus);
    gameStatus.set_stage_countdown_sec(210);
    gameData.updateGameStatus(gameStatus);
    QCOMPARE(voiceSpy.last().at(0).toInt(),
             static_cast<int>(RM::RuneVoiceType::Large));
    QCOMPARE(voiceSpy.last().at(1).toInt(), 1);
    QCOMPARE(voiceSpy.count(), 3);
  }

  void testRuneStatusChangeLoggingIgnoresRepeatedAndInvalidPackets() {
    GameData gameData;
    robomaster::RuneStatusSync runeStatus;
    QStringList capturedMessages;

    g_runeStatusLogMessages = &capturedMessages;
    const QtMessageHandler previousHandler =
        qInstallMessageHandler(captureRuneStatusLog);

    runeStatus.set_rune_status(1);
    gameData.updateRuneStatusSync(runeStatus);
    gameData.updateRuneStatusSync(runeStatus);

    runeStatus.set_rune_status(4);
    gameData.updateRuneStatusSync(runeStatus);

    runeStatus.set_rune_status(2);
    gameData.updateRuneStatusSync(runeStatus);
    gameData.updateRuneStatusSync(runeStatus);

    qInstallMessageHandler(previousHandler);
    g_runeStatusLogMessages = nullptr;

    QCOMPARE(capturedMessages.size(), 2);
    QVERIFY(capturedMessages.at(0).contains(QStringLiteral("old=unknown new=1")));
    QVERIFY(capturedMessages.at(0).contains(QStringLiteral("stage=0")));
    QVERIFY(capturedMessages.at(0).contains(QStringLiteral("gameTime=420")));
    QVERIFY(capturedMessages.at(1).contains(QStringLiteral("old=1 new=2")));
  }
};

QTEST_MAIN(TestGameData)
#include "test_game_data.moc"
