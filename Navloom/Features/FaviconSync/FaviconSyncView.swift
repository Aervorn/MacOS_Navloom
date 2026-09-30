//
//  FaviconSyncView.swift
//  Navloom
//
//  Created by Aervorn on 29/09/2026.
//


import SwiftUI

struct FaviconSyncView: View {
    var body: some View {
        ContentUnavailableView(
            "FaviconSync",
            systemImage: "star.square",
            description: Text("Récupère les favicons manquants de tes favoris.")
        )
        .navigationTitle("FaviconSync")
    }
}

#Preview {
    FaviconSyncView()
}