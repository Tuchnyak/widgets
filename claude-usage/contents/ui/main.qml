import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Rings are shown inline in any panel or on the desktop; no popup.
    preferredRepresentation: fullRepresentation

    // Unofficial endpoint, token is read from Claude Code credentials and
    // passed to curl via stdin (not visible in the process list).
    readonly property string command:
        "jq -r '\"Authorization: Bearer \" + .claudeAiOauth.accessToken' \"$HOME/.claude/.credentials.json\" | " +
        "curl -sS --max-time 15 -H @- -H 'anthropic-beta: oauth-2025-04-20' -w '\\n%{http_code}' " +
        "https://api.anthropic.com/api/oauth/usage"

    // -1 means "no data yet"
    property real fiveUsed: -1
    property real weekUsed: -1
    property string fiveReset: ""
    property string weekReset: ""
    property var updated: null
    property bool failed: false
    property date now: new Date()

    function colorFor(value) {
        if (failed || value < 0) return Kirigami.Theme.disabledTextColor
        if (value >= 95) return Kirigami.Theme.negativeTextColor
        if (value >= 80) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.highlightColor
    }

    function timeLeft(iso) {
        const ms = new Date(iso) - now
        if (isNaN(ms)) return ""
        if (ms <= 0) return "сброс наступил"
        const mins = Math.round(ms / 60000)
        const d = Math.floor(mins / 1440)
        const h = Math.floor((mins % 1440) / 60)
        const m = mins % 60
        const left = d > 0 ? d + " дн " + h + " ч" : h > 0 ? h + " ч " + m + " мин" : m + " мин"
        return "сброс через " + left
    }

    function line(title, used, reset) {
        if (used < 0) return title + ": нет данных"
        const t = timeLeft(reset)
        return title + ": " + Math.round(used) + "%" + (t ? ", " + t : "")
    }

    toolTipMainText: "Claude Pro"
    toolTipSubText: {
        let text = line("5 часов", fiveUsed, fiveReset) + "\n" + line("Неделя", weekUsed, weekReset)
        if (failed) {
            text += updated
                ? "\nДанные устарели, последнее обновление: " + Qt.formatTime(updated, "HH:mm")
                : "\nНе удалось получить данные. Войдите в Claude Code."
        }
        return text
    }

    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: [root.command]
        interval: 600000 // 10 minutes
        onNewData: (source, data) => {
            const out = data["stdout"] || ""
            const nl = out.lastIndexOf("\n")
            let ok = false
            if (nl >= 0 && out.slice(nl + 1).trim() === "200") {
                try {
                    const j = JSON.parse(out.slice(0, nl))
                    if (j.seven_day) {
                        // a missing five_hour is treated as an inactive window (0%)
                        const five = j.five_hour || {}
                        root.fiveUsed = typeof five.utilization === "number" ? five.utilization : 0
                        root.fiveReset = five.resets_at || ""
                        root.weekUsed = j.seven_day.utilization
                        root.weekReset = j.seven_day.resets_at || ""
                        root.updated = new Date()
                        ok = true
                    }
                } catch (e) {}
            }
            root.failed = !ok
        }
    }

    component Ring: Item {
        id: ring
        property real value: -1
        readonly property real d: Math.min(width, height)
        readonly property real stroke: Math.max(2, d * 0.16)
        readonly property real r: (d - stroke) / 2

        Shape {
            anchors.centerIn: parent
            width: ring.d
            height: ring.d
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                strokeWidth: ring.stroke
                PathAngleArc {
                    centerX: ring.d / 2; centerY: ring.d / 2
                    radiusX: ring.r; radiusY: ring.r
                    startAngle: 0; sweepAngle: 360
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.colorFor(ring.value)
                strokeWidth: ring.stroke
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: ring.d / 2; centerY: ring.d / 2
                    radiusX: ring.r; radiusY: ring.r
                    startAngle: -90
                    sweepAngle: 360 * Math.min(100, Math.max(0, ring.value)) / 100
                }
            }
        }
        Text {
            anchors.centerIn: parent
            width: ring.d - 2 * ring.stroke
            horizontalAlignment: Text.AlignHCenter
            text: ring.value < 0 ? "–" : Math.round(ring.value)
            color: Kirigami.Theme.textColor
            font.family: Kirigami.Theme.defaultFont.family
            font.pixelSize: ring.d * 0.48
            fontSizeMode: Text.Fit
            minimumPixelSize: 6
        }
    }

    fullRepresentation: GridLayout {
        id: grid
        readonly property bool vertical:
            Plasmoid.formFactor === PlasmaCore.Types.Vertical
            || (Plasmoid.formFactor === PlasmaCore.Types.Planar && height > width)

        // Panel thickness comes from the panel (root size), not from this
        // layout's own size, otherwise it gets stuck at the minimum.
        readonly property bool inVerticalPanel: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real side: inVerticalPanel ? root.width : root.height
        readonly property real minSide: Kirigami.Units.iconSizes.small
        readonly property real spacing: Kirigami.Units.smallSpacing

        columns: vertical ? 1 : 2
        rowSpacing: spacing
        columnSpacing: spacing

        // grow across the panel, take only what two rings need along it
        Layout.fillWidth: inVerticalPanel
        Layout.fillHeight: !inVerticalPanel
        Layout.minimumWidth: inVerticalPanel ? minSide : 2 * minSide + spacing
        Layout.minimumHeight: inVerticalPanel ? 2 * minSide + spacing : minSide
        Layout.preferredWidth: inVerticalPanel ? side : 2 * side + spacing
        Layout.preferredHeight: inVerticalPanel ? 2 * side + spacing : side

        Ring {
            value: root.fiveUsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: grid.minSide
            Layout.minimumHeight: grid.minSide
        }
        Ring {
            value: root.weekUsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: grid.minSide
            Layout.minimumHeight: grid.minSide
        }

        // refresh "time left" before the tooltip is shown
        HoverHandler {
            onHoveredChanged: if (hovered) root.now = new Date()
        }
    }
}
