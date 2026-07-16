# arctis-mixer

A zero-configuration, native Rust daemon that bridges SteelSeries ChatMix physical dials to PipeWire virtual audio sinks on Linux.

No manual configuration is required. Simply install, plug in your headset, and use your physical ChatMix dial to dynamically balance game and chat audio streams in real time.

---

## Features

*   **Zero-Configuration:** Installs cleanly via the AUR, automatically sets up systemd user services, and configures USB permissions without manual intervention.
*   **Native PipeWire Integration:** Programs virtual audio sinks (`Arctis_Game` and `Arctis_Chat`) directly through programmatic APIs—no shell scripts or fragile command-line wrappers required.
*   **Modular Hardware Drivers:** Built with an extensible, trait-based driver architecture. Features native support for the SteelSeries Arctis Nova 7 (including the World of Warcraft Edition) with easy expandability for other USB HID models.
*   **Adaptive Port Mapping:** Automatically detects and switches between standard Stereo layouts (`playback_FL`/`playback_FR`) and Pro-Audio profiles (`playback_AUX0`/`playback_AUX1`).
*   **Robust Keep-Alive Loop:** Gracefully handles physical USB disconnects, computer sleep states, and system reboots, automatically reconnecting the physical dial interface when detected.

---

## Architecture

The utility divides responsibilities across three clean components:

1.  **`src/drivers/` (Hardware Abstraction):** Listens to USB interrupt packets over `hidapi` and translates raw dials into a unified `MixerEvent::ChatMixBalance(0.0 - 1.0)`.
2.  **`src/pipewire_mgr.rs` (Audio Routing):** Instantiates virtual null-sinks on PipeWire and binds their channels directly to the physical headset's hardware channels.
3.  **`src/main.rs` (The Orchestrator):** Runs the background monitoring loops and converts dial positions into mapped volume adjustments.

---

## Installation

### Arch Linux (AUR)

If you are using Arch Linux or an Arch-based distribution, you can install `arctis-mixer` directly from the AUR using your favorite AUR helper:

```bash
yay -S arctis-mixer
```

Once installed, the package helper automatically takes care of compiling the binary, placing user presets, installing USB `udev` permission rules, and enabling the systemd user service.

The background daemon will spin up automatically on your next login!

### Manual Installation (From Source)

If you prefer to build, run, or debug the utility manually:

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/yourusername/arctis-mixer.git](https://github.com/yourusername/arctis-mixer.git)
    cd arctis-mixer
    ```

2.  **Build the Release Binary:**
    ```bash
    cargo build --release
    ```

3.  **Install the Systemd User Service & Udev Rules:**
    Copy the systemd service and udev rule templates from the `contrib/` folder:
    ```bash
    # Install the compiled binary
    sudo cp target/release/arctis-mixer /usr/bin/

    # Install udev rules so you can access the USB HID interface without root
    sudo cp contrib/99-arctis-mixer.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger

    # Install the systemd user service
    mkdir -p ~/.config/systemd/user/
    cp contrib/arctis-mixer.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now arctis-mixer.service
    ```

---

## Configuration & Usage

Once installed and running, you do not need to interact with the command line.

1.  Open your system sound settings (e.g., Pavucontrol, Gnome Sound, or KDE Audio Settings).
2.  Set your system's default audio output device to **Arctis Game** (`Arctis_Game`).
3.  Configure your communication clients (Discord, TeamSpeak, Matrix, Steam Chat) to output their voice audio specifically to the **Arctis Chat** (`Arctis_Chat`) sink.
4.  Rotate your headset's physical ChatMix dial. You will immediately hear the relative volumes of your game and voice communication streams shift in real time!

---

## Development & Releases

To package, publish, or release updates for this application, a unified release orchestrator is provided:

```bash
./release.sh
```

Running `./release.sh` will:

1.  Run pre-flight checks (lints, formatting, unit tests) and build the optimized production binary.
2.  Interactively publish the package workspace to [crates.io](https://crates.io/).
3.  Detect your sibling AUR repository, automatically sync version numbers from `Cargo.toml`, recalculate SHA256 file hashes, generate the `.SRCINFO` manifest, and push updates upstream to the AUR servers.

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0). See the [LICENSE](LICENSE) file for the full license text.