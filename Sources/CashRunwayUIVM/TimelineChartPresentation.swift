import Foundation

/// Presentation rules shared by Timeline chart renderers.
public enum TimelineChartPresentation {
    /// A guide that hugs the baseline does not communicate a distinct value and can
    /// be mistaken for the baseline itself, so it stays hidden.
    public static func showsReferenceLine(value: Int64, scale: CGFloat, minimumDistance: CGFloat) -> Bool {
        value > 0 && scale > 0 && CGFloat(value) * scale >= minimumDistance
    }
}
