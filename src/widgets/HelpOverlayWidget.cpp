#include "HelpOverlayWidget.h"

#include <QGraphicsDropShadowEffect>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QResizeEvent>
#include <QVBoxLayout>

namespace RM {

HelpOverlayWidget::HelpOverlayWidget(QWidget *parent) : QWidget(parent) {
  setAttribute(Qt::WA_TranslucentBackground);
  setAttribute(Qt::WA_StyledBackground, false);
  setFocusPolicy(Qt::NoFocus);

  m_panel = new QWidget(this);
  m_panel->setObjectName("helpOverlayPanel");
  m_panel->setFixedSize(780, 400);
  m_panel->setAttribute(Qt::WA_StyledBackground, true);
  m_panel->setStyleSheet(
      "#helpOverlayPanel {"
      " background: rgba(19, 30, 39, 247);"
      " border: 1px solid #647c8c;"
      " border-radius: 3px;"
      "}");

  auto *shadow = new QGraphicsDropShadowEffect(m_panel);
  shadow->setBlurRadius(28);
  shadow->setOffset(0, 10);
  shadow->setColor(QColor(0, 0, 0, 120));
  m_panel->setGraphicsEffect(shadow);

  auto *mainLayout = new QVBoxLayout(m_panel);
  mainLayout->setContentsMargins(30, 24, 30, 24);
  mainLayout->setSpacing(12);

  auto *title = new QLabel(QStringLiteral("快捷键"), m_panel);
  title->setStyleSheet(
      "color: #F3F6F7; font-family: 'Microsoft YaHei';"
      " font-size: 26px; font-weight: 700; border: none; background: transparent;");
  mainLayout->addWidget(title);

  auto *subtitle = new QLabel(QStringLiteral("按住 F12 查看，松开即关闭"), m_panel);
  subtitle->setStyleSheet(
      "color: rgba(220, 228, 232, 180); font-family: 'Microsoft YaHei';"
      " font-size: 13px; border: none; background: transparent;");
  mainLayout->addWidget(subtitle);

  auto *grid = new QGridLayout();
  grid->setHorizontalSpacing(18);
  grid->setVerticalSpacing(10);

  grid->addWidget(createHelpItem(QStringLiteral("P"),
                                 QStringLiteral("设置与登录，选择赛项和车位"),
                                 m_panel),
                  0, 0);
  grid->addWidget(createHelpItem(QStringLiteral("~"),
                                 QStringLiteral("按住查看伤害和模块状态"),
                                 m_panel),
                  0, 1);
  grid->addWidget(createHelpItem(QStringLiteral("Tab"),
                                 QStringLiteral("按住查看双方战况，松开返回"),
                                 m_panel),
                  1, 0);
  grid->addWidget(createHelpItem(QStringLiteral("O / I"),
                                 QStringLiteral("操作手的 17mm / 42mm 补给面板"),
                                 m_panel),
                  1, 1);
  grid->addWidget(createHelpItem(QStringLiteral("M"),
                                 QStringLiteral("打开或收起大地图"),
                                 m_panel),
                  2, 0);
  grid->addWidget(createHelpItem(QStringLiteral("H"),
                                 QStringLiteral("打开本车适用的兑换或支援面板"),
                                 m_panel),
                  2, 1);

  grid->addWidget(createHelpItem(QStringLiteral("Ctrl+T"),
                                 QStringLiteral("全屏主图传与战术指挥屏切换"),
                                 m_panel),
                  3, 0);
  grid->addWidget(createHelpItem(QStringLiteral("Ctrl+Y"),
                                 QStringLiteral("指挥屏切换地图与工业相机优先"),
                                 m_panel),
                  3, 1);
  mainLayout->addLayout(grid);
}

QWidget *HelpOverlayWidget::createHelpItem(const QString &keyText,
                                           const QString &description,
                                           QWidget *parent) {
  auto *item = new QWidget(parent);
  item->setAttribute(Qt::WA_StyledBackground, true);
  item->setStyleSheet(
      "background: #1e303d;"
      "border: 1px solid #354a59;"
      "border-radius: 2px;");

  auto *layout = new QHBoxLayout(item);
  layout->setContentsMargins(10, 8, 10, 8);
  layout->setSpacing(12);

  auto *keyLabel = new QLabel(keyText, item);
  keyLabel->setAlignment(Qt::AlignCenter);
  keyLabel->setFixedSize(76, 33);
  keyLabel->setStyleSheet(
      "background: #162530;"
      "border: 1px solid #607781;"
      "border-radius: 2px;"
      "color: #e5f2fa;"
      "font-family: 'Microsoft YaHei';"
      "font-size: 15px;"
      "font-weight: 700;");

  auto *descLabel = new QLabel(description, item);
  descLabel->setWordWrap(true);
  descLabel->setStyleSheet(
      "background: transparent; border: none;"
      "color: rgba(231, 236, 239, 0.92);"
      "font-family: 'Microsoft YaHei';"
      "font-size: 14px;");

  layout->addWidget(keyLabel, 0, Qt::AlignTop);
  layout->addWidget(descLabel, 1);

  return item;
}

void HelpOverlayWidget::paintEvent(QPaintEvent *event) {
  Q_UNUSED(event);

  QPainter painter(this);
  painter.setRenderHint(QPainter::Antialiasing);
  painter.fillRect(rect(), QColor(8, 10, 14, 132));
}

void HelpOverlayWidget::resizeEvent(QResizeEvent *event) {
  QWidget::resizeEvent(event);

  if (!m_panel) {
    return;
  }

  m_panel->move((width() - m_panel->width()) / 2,
                (height() - m_panel->height()) / 2);
}

} // namespace RM
