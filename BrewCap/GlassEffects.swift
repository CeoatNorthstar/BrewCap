//
//  GlassEffects.swift
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

import SwiftUI

// MARK: - Glass Background Modifier

struct GlassBackgroundModifier: ViewModifier {
    var material: Material = .regular
    var tint: Color = .white
    var tintOpacity: Double = 0.02
    
    func body(content: Content) -> some View {
        content
            .background(material)
            .background(tint.opacity(tintOpacity))
    }
}

extension View {
    func glassBackground(material: Material = .regular, tint: Color = .white, tintOpacity: Double = 0.02) -> some View {
        modifier(GlassBackgroundModifier(material: material, tint: tint, tintOpacity: tintOpacity))
    }
}

// MARK: - Glass Card Modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var borderOpacity: Double = 0.15
    var material: Material = .thin
    var shadowRadius: CGFloat = 10
    
    func body(content: Content) -> some View {
        content
            .background(material)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: shadowRadius, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, borderOpacity: Double = 0.15, material: Material = .thin, shadowRadius: CGFloat = 10) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity, material: material, shadowRadius: shadowRadius))
    }
}

// MARK: - Monochrome Color Scheme

struct MonochromeColors {
    static let primary = Color.primary
    static let primaryMedium = Color.primary.opacity(0.95)
    static let secondary = Color.secondary
    static let tertiary = Color.secondary.opacity(0.7)
    static let quaternary = Color.secondary.opacity(0.4)
    static let border = Color.primary.opacity(0.1)
    static let overlay = Color.primary.opacity(0.05)
    static let accent = Color.accentColor
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(prominent ? Material.thick : Material.regular)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.15 : (prominent ? 0.08 : 0.0)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(prominent: true) }
}

// MARK: - Glass Toggle Style

struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            
            ZStack {
                // Background track
                Capsule()
                    .fill(Material.thin)
                    .overlay {
                        if configuration.isOn {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.2))
                        }
                    }
                    .frame(width: 51, height: 31)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                
                // Knob
                Circle()
                    .fill(Material.regular)
                    .overlay(
                        Circle()
                            .fill(configuration.isOn ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                    .offset(x: configuration.isOn ? 10 : -10)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

extension ToggleStyle where Self == GlassToggleStyle {
    static var glass: GlassToggleStyle { GlassToggleStyle() }
}

// MARK: - Glass Divider

struct GlassDivider: View {
    var opacity: Double = 0.1
    
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(opacity))
            .frame(height: 1)
    }
}

// MARK: - Glass Progress Bar

struct GlassProgressView: View {
    var value: Double
    var total: Double = 100.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Material.thin)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                
                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .fill(Material.ultraThin)
                    )
                    .frame(width: max(8, geometry.size.width * (value / total)))
                    .animation(.spring(response: 0.4), value: value)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Glass Slider Style

struct GlassSliderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(.accentColor)
    }
}

extension View {
    func glassSlider() -> some View {
        modifier(GlassSliderStyle())
    }
}

// MARK: - Glass Picker Segment Style

struct GlassPickerSegmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .pickerStyle(.segmented)
    }
}

extension View {
    func glassPicker() -> some View {
        modifier(GlassPickerSegmentModifier())
    }
}

// MARK: - Glass Text Field

struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(10)
            .background(.ultraThinMaterial.opacity(0.2))
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
    }
}

extension TextFieldStyle where Self == GlassTextFieldStyle {
    static var glass: GlassTextFieldStyle { GlassTextFieldStyle() }
}

// MARK: - Glass Window Background

struct GlassWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Material.ultraThin)
    }
}

extension View {
    func glassWindowBackground() -> some View {
        modifier(GlassWindowBackground())
    }
}

// MARK: - Floating Glass Effect (for panels/sections)

struct FloatingGlassModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Material.regular)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func floatingGlass(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(FloatingGlassModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
