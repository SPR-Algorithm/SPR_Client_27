#pragma once

#include <QSizeF>
#include <QString>
#include <QList>

namespace RM {

enum class MatchProfile { Legacy2026, Rmuc2027, Rmul3v3, Rmul1v1 };

inline MatchProfile parseMatchProfile(const QString &name) {
  if (name == QStringLiteral("rmuc2027"))
    return MatchProfile::Rmuc2027;
  if (name == QStringLiteral("rmul3v3"))
    return MatchProfile::Rmul3v3;
  if (name == QStringLiteral("rmul1v1"))
    return MatchProfile::Rmul1v1;
  return MatchProfile::Legacy2026;
}

inline bool is2027(MatchProfile profile) {
  return profile != MatchProfile::Legacy2026;
}

inline QList<int> playerSeats(MatchProfile profile) {
  switch (profile) {
  case MatchProfile::Rmuc2027: return {1, 3, 4, 6};
  case MatchProfile::Rmul3v3: return {1, 3};
  case MatchProfile::Rmul1v1: return {3};
  case MatchProfile::Legacy2026: return {1, 2, 3, 4, 6, 7};
  }
  return {};
}

inline QSizeF fieldSize(MatchProfile profile) {
  switch (profile) {
  case MatchProfile::Rmul3v3: return {12, 8};
  case MatchProfile::Rmul1v1: return {5, 5};
  default: return {28, 15};
  }
}

// The wire sequence is fixed, including unoccupied slots in RMUL.
inline constexpr int globalUnitSlots2027[] = {1, 3, 4, 7};

} // namespace RM
