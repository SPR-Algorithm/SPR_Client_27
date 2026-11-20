import QtQuick

Image {
    id: root

    required property string kind
    property color tint: "#b0c3cf"
    readonly property var paths: ({
        map: "m3 5 6-2 6 3 6-2v15l-6 2-6-3-6 2zm6-2v15m6-12v15",
        squad: "m12 3 4 4-4 4-4-4zm-6 9 4 4-4 4-4-4zm12 0 4 4-4 4-4-4z",
        coin: "m7 3 10 0 5 9-5 9H7l-5-9zM8 12h8m-4-4v8",
        base: "m12 2 9 5v10l-9 5-9-5V7zm0 5 4 2.5v5L12 17l-4-2.5v-5z",
        outpost: "M21.2 12a9.2 9.2 0 1 1-18.4 0 9.2 9.2 0 0 1 18.4 0zm-9.2-5 3 5-3 5-3-5z",
        shield: "m12 3 8 3v6c0 4-4 7-8 9-4-2-8-5-8-9V6zm-4 9 3 3 5-6",
        camera: "M3 7h12v10H3zm12 3 6-3v10l-6-3zM7 12h2",
        event: "M4 3h16v18H4zM8 7h8M8 11h8M8 15h5",
        analysis: "M4 4v16h17M7 15l4-5 4 2 5-6m-4 0h4v4",
        revive: "M4.3 8.6A8 8 0 1 1 4.7 16m-.4-11v3.8h3.8M12 8v4l2.6 1.7",
        recovery: "M9 3h6v6h6v6h-6v6H9v-6H3V9h6z",
        dart: "M20.9 2.4l.7.7-2 5-8.3 8.3-.5 4-3.6 1.3.6-3.5-3.5.6 1.3-3.6 4-.5 8.3-8.3z"
    })

    width: 15
    height: 15
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.ceil(width * 2)
    sourceSize.height: Math.ceil(height * 2)
    source: kind in paths ? "data:image/svg+xml," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
        + '<path stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round" stroke="' + String(tint)
        + '" fill="' + (kind === "dart" ? String(tint) : "none") + '" d="' + paths[kind] + '"/></svg>') : ""
}
