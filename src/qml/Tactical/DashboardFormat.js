.pragma library

function number(value) {
    return value === undefined || value === null ? "—" : String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function ratio(value, maximum) {
    return value !== undefined && maximum > 0 ? Math.max(0, Math.min(1, value / maximum)) : 0
}

function redSurface(leadingSide) {
    return leadingSide === 1 ? "#59333e" : leadingSide === 2 ? "#76515b" : "#694651"
}

function blueSurface(leadingSide) {
    return leadingSide === 2 ? "#23415f" : leadingSide === 1 ? "#415f7d" : "#345474"
}

function heavyAccent(blue) {
    return blue ? "#8bcdff" : "#fa9284"
}

function heavyGold() {
    return "#ffcb77"
}

function heavyName(blue, hero) {
    const muted = "#9db0bf"
    return "重装<span style='color:" + muted + "'>（<span style='color:"
        + (hero ? muted : heavyAccent(blue)) + "'>工</span>/<span style='color:"
        + (hero ? heavyGold() : muted) + "'>雄</span>）</span>"
}

function heavyStatus(heavy) {
    if (heavy?.installedAt > 0)
        return "安装成功"
    if (heavy?.allowed === true)
        return "可安装 · 待确认"
    return heavy?.allowed === false ? "未获安装权限" : "形态待同步"
}

function portrait(blue, number, heavyInstalled) {
    const team = blue ? "blue" : "red"
    if (number === 1) {
        if (heavyInstalled === undefined)
            return "qrc:/images/dashboard/" + team + "-heavy.svg"
        return "qrc:/images/top_robots/" + team + "_teammate_avatar_"
            + (heavyInstalled ? "hero" : "engineer") + ".png"
    }
    const role = number === 6 ? "aerial" : number === 7 ? "sentry" : "infantry"
    return "qrc:/images/dashboard/" + team + "-" + role + ".svg"
}
