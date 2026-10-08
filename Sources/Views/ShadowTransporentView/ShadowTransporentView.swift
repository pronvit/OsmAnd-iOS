//
//  ShadowTransporentView.swift
//  OsmAnd Maps
//
//  Created by Oleksandr Panchenko on 08.09.2023.
//  Copyright © 2023 OsmAnd. All rights reserved.
//

@objcMembers
class ShadowTransporentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        guard !bounds.isEmpty else {
            return
        }
        let corners = roundingCorners
        let path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0, dy: 0),
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: 4, height: 4))
        let hole = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: 4, height: 4))
            .reversing()
        path.append(hole)
        layer.shadowPath = path.cgPath
    }

    private var roundingCorners: UIRectCorner {
        let mask = layer.maskedCorners
        var corners: UIRectCorner = []
        if mask.contains(.layerMinXMinYCorner) {
            corners.insert(.topLeft)
        }
        if mask.contains(.layerMaxXMinYCorner) {
            corners.insert(.topRight)
        }
        if mask.contains(.layerMinXMaxYCorner) {
            corners.insert(.bottomLeft)
        }
        if mask.contains(.layerMaxXMaxYCorner) {
            corners.insert(.bottomRight)
        }
        return corners.isEmpty ? .allCorners : corners
    }
}

@objc(OAShadowTransporentTouchesPassView)
@objcMembers
final class ShadowTransporentTouchesPassView: ShadowTransporentView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view === self {
            return nil
        }
        return view
    }
}
