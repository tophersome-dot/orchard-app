import CoreGraphics
import Foundation

struct PlotLayout: Equatable {
    var canvas: CGSize
    var house: CGPoint
    var sign: CGPoint
    var tractor: CGPoint
    var greenhouse: CGPoint
    var slots: [String: CGPoint]

    static func make(orchard: [String], beds: [String], trellis: [String], lab: [String]) -> PlotLayout {
        let width: CGFloat = 960
        var slots: [String: CGPoint] = [:]
        var y: CGFloat = 56

        let orchardColumns = 4
        if orchard.isEmpty {
            y += 24
        } else {
            let rows = Int(ceil(Double(orchard.count) / Double(orchardColumns)))
            for (index, id) in orchard.enumerated() {
                let column = index % orchardColumns
                let row = index / orchardColumns
                slots[id] = CGPoint(
                    x: 130 + CGFloat(column) * 230,
                    y: y + 90 + CGFloat(row) * 200
                )
            }
            y += CGFloat(rows) * 200 + 16
        }

        let house = CGPoint(x: width / 2, y: y + 120)
        let sign = CGPoint(x: width / 2, y: y + 248)
        let tractor = CGPoint(x: width / 2 + 250, y: y + 160)
        y += 300

        let bedRows = max(1, Int(ceil(Double(beds.count) / 2.0)))
        let trellisRows = max(1, Int(ceil(Double(trellis.count) / 2.0)))
        let groundRows = max(bedRows, trellisRows)
        for (index, id) in beds.enumerated() {
            slots[id] = CGPoint(
                x: 160 + CGFloat(index % 2) * 210,
                y: y + 90 + CGFloat(index / 2) * 190
            )
        }
        for (index, id) in trellis.enumerated() {
            slots[id] = CGPoint(
                x: 620 + CGFloat(index % 2) * 200,
                y: y + 90 + CGFloat(index / 2) * 190
            )
        }
        y += CGFloat(groundRows) * 190 + 36

        let greenhouse = CGPoint(x: 220, y: y + 110)
        let labColumns = 3
        for (index, id) in lab.enumerated() {
            slots[id] = CGPoint(
                x: 430 + CGFloat(index % labColumns) * 160,
                y: y + 100 + CGFloat(index / labColumns) * 160
            )
        }
        let labRows = max(1, Int(ceil(Double(lab.count) / Double(labColumns))))
        y += CGFloat(labRows) * 160 + 70

        return PlotLayout(
            canvas: CGSize(width: width, height: y),
            house: house,
            sign: sign,
            tractor: tractor,
            greenhouse: greenhouse,
            slots: slots
        )
    }
}
