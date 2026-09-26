import SwiftUI
import SideBCore

// MARK: - QuickResultCardRow

struct QuickResultCardRow: View {
    let card: BrowseCardRecord
    var isHero: Bool = false
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    private var isArtist: Bool {
        card.kind.lowercased() == "artist"
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Miniatura optimizada CDN (Google CDN 96px ~2KB)
                if let thumb = card.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: isHero ? 120 : 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: isHero ? 48 : 38, height: isHero ? 48 : 38)) { img in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderIcon
                    }
                    .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                    .overlay(
                        isArtist
                            ? AnyView(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                            : AnyView(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    )
                } else {
                    placeholderIcon
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: isHero ? 14 : 13, weight: isHero ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(kindDisplayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHero ? Color.sidebAccent : .secondary)
                        
                        if let sub = card.subtitle, !sub.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                if isHero {
                    Text("Mejor resultado")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                
                Image(systemName: isArtist || card.kind == "album" || card.kind == "playlist" ? "chevron.right" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.6))
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, isHero ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var kindDisplayName: String {
        switch card.kind.lowercased() {
        case "artist": return "Artista"
        case "album": return "Álbum"
        case "playlist": return "Playlist"
        case "song": return "Canción"
        default: return card.kind.capitalized
        }
    }
    
    private var placeholderIcon: some View {
        ZStack {
            if isArtist {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: "person.fill")
                    .font(.system(size: isHero ? 16 : 14))
                    .foregroundStyle(.secondary)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
                Image(systemName: card.kind == "album" ? "opticaldisc" : "music.note")
                    .font(.system(size: isHero ? 16 : 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: isHero ? 48 : 38, height: isHero ? 48 : 38)
    }
}

// MARK: - QuickResultSongRow

struct QuickResultSongRow: View {
    let song: SongItemRecord
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Miniatura 38x38
                if let thumb = song.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 38, height: 38)) { img in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                }
                
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text("Canción")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.8))
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        
                        Text(song.artists)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if let duration = song.duration {
                    Text(duration)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.sidebAccent : Color.secondary.opacity(0.5))
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
