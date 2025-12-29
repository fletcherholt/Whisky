//
//  PinAddView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit

struct PinAddView: View {
    let bottle: Bottle
    @State private var showingSheet = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.purple.opacity(isHovering ? 0.15 : 0))
                    .blur(radius: 10)

                Button {
                    showingSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .foregroundStyle(.purple.opacity(isHovering ? 1 : 0.6))
                        .frame(width: 40, height: 40)
                        .scaleEffect(isHovering ? 1.1 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
                }
                .buttonStyle(.plain)
            }

            Text("pin.addGame")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: 100, height: 100)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.purple.opacity(isHovering ? 0.5 : 0.2))
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .sheet(isPresented: $showingSheet) {
            PinCreationView(bottle: bottle)
        }
    }
}

#Preview {
    PinAddView(bottle: Bottle(bottleUrl: URL(filePath: "")))
}
