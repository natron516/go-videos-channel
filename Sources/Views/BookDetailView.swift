import SwiftUI
import UIKit

#if !os(tvOS)

struct BookDetailView: View {
    let book: GOBook

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.appBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header: cover + title/author
                    HStack(alignment: .top, spacing: 20) {
                        // Cover
                        Group {
                            if let urlStr = book.coverImageUrl, let url = URL(string: urlStr) {
                                CachedAsyncImage(url: url) {
                                    Color.white.opacity(0.08)
                                        .overlay(
                                            Image(systemName: "book.fill")
                                                .font(.system(size: 30))
                                                .foregroundColor(.secondary)
                                        )
                                }
                            } else {
                                Color.white.opacity(0.08)
                                    .overlay(
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(.secondary)
                                    )
                            }
                        }
                        .frame(width: 120, height: 180)
                        .clipped()
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("by \(book.author)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)

                            // Quick purchase buttons
                            VStack(alignment: .leading, spacing: 10) {
                                if let amazonUrl = book.amazonUrl, !amazonUrl.isEmpty {
                                    PurchaseButton(label: "Amazon", icon: "cart.fill", url: amazonUrl, color: .orange)
                                }
                                if let kindleUrl = book.kindleUrl, !kindleUrl.isEmpty {
                                    PurchaseButton(label: "Kindle", icon: "ipad", url: kindleUrl, color: .blue)
                                }
                                if let audiobookUrl = book.audiobookUrl, !audiobookUrl.isEmpty {
                                    PurchaseButton(label: "Audiobook", icon: "headphones", url: audiobookUrl, color: .purple)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Description
                    if !book.description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About This Book")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(book.description)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Full-width purchase buttons
                    let hasAmazon = !(book.amazonUrl ?? "").isEmpty
                    let hasKindle = !(book.kindleUrl ?? "").isEmpty
                    let hasAudiobook = !(book.audiobookUrl ?? "").isEmpty

                    if hasAmazon || hasKindle || hasAudiobook {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Purchase")
                                .font(.headline)
                                .foregroundColor(.white)

                            if hasAmazon, let url = book.amazonUrl {
                                FullWidthPurchaseButton(label: "Buy on Amazon", icon: "cart.fill", url: url, color: .orange)
                            }
                            if hasKindle, let url = book.kindleUrl {
                                FullWidthPurchaseButton(label: "Get Kindle Edition", icon: "ipad", url: url, color: .blue)
                            }
                            if hasAudiobook, let url = book.audiobookUrl {
                                FullWidthPurchaseButton(label: "Get Audiobook", icon: "headphones", url: url, color: .purple)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Purchase Button (compact)
struct PurchaseButton: View {
    let label: String
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(label)
                    .font(.caption.bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(color))
        }
    }
}

// MARK: - Full-width Purchase Button
struct FullWidthPurchaseButton: View {
    let label: String
    let icon: String
    let url: String
    let color: Color

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.bold())
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.85))
            )
        }
    }
}

// MARK: - URL opener — opens web URL directly, lets iOS universal links handle app routing
private func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }

    // Try Kindle app deep link for Amazon/Kindle URLs
    if urlString.contains("amazon.com") || urlString.contains("kindle") {
        // Extract ASIN from Amazon URL if possible (e.g. /dp/XXXXXXXXX)
        if let asinRange = urlString.range(of: "/dp/"),
           let asin = urlString[asinRange.upperBound...].split(separator: "/").first.map(String.init),
           let kindleURL = URL(string: "kindle://book?action=open&asin=\(asin)") {
            UIApplication.shared.open(kindleURL, options: [:]) { opened in
                if !opened {
                    // Kindle app not installed — fall back to web
                    UIApplication.shared.open(url)
                }
            }
            return
        }
    }

    // Try Audible app for Audible URLs
    if urlString.contains("audible.com") || urlString.contains("audible") {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                UIApplication.shared.open(url)
            }
        }
        return
    }

    // Default: universal link → Safari fallback
    UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
        if !opened {
            UIApplication.shared.open(url)
        }
    }
}

#endif
