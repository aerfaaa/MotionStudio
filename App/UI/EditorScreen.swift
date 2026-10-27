
Menu {
    Button {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingPhotoPicker = true
        }
    } label: {
        Label("Photo Library", systemImage: "photo.on.rectangle")
    }

    Button {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingFileImporter = true
        }
    } label: {
        Label("Files", systemImage: "folder")
    }
} label: {
    Image(systemName: "photo.badge.plus")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
.accessibilityLabel("Import image")
