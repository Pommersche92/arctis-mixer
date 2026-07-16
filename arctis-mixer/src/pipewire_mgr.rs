use std::process::Command;
use std::time::Duration;
use std::thread;
use anyhow::{anyhow, Result};

pub struct PipewireManager {
    physical_sink: String,
    left_target: String,
    right_target: String,
}

impl PipewireManager {
    pub fn new() -> Result<Self> {
        let mut physical_sink = String::new();
        
        // Find the physical headset sink dynamically
        for _ in 0..20 {
            let output = Command::new("pactl")
                .args(["list", "sinks", "short"])
                .output()?;
            let stdout = String::from_utf8_lossy(&output.stdout);
            
            for line in stdout.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    let sink_name = parts[1];
                    if sink_name.contains("SteelSeries_Arctis_Nova_7") && !sink_name.starts_with("Arctis_") {
                        physical_sink = sink_name.to_string();
                        break;
                    }
                }
            }
            if !physical_sink.is_empty() {
                break;
            }
            thread::sleep(Duration::from_millis(250));
        }

        if physical_sink.is_empty() {
            println!("Warning: Headset not found. Falling back to default Pro-Audio name.");
            physical_sink = "alsa_output.usb-SteelSeries_Arctis_Nova_7_WOW_Edition-00.pro-output-0".to_string();
        }

        // Determine target ports (Pro Audio AUX vs Standard FL/FR)
        let ports_output = Command::new("pw-link")
            .args(["-io"])
            .output()?;
        let ports_stdout = String::from_utf8_lossy(&ports_output.stdout);
        
        let (left_target, right_target) = if ports_stdout.contains("playback_AUX0") {
            ("playback_AUX0".to_string(), "playback_AUX1".to_string())
        } else {
            ("playback_FL".to_string(), "playback_FR".to_string())
        };

        Ok(Self {
            physical_sink,
            left_target,
            right_target,
        })
    }

    pub fn setup_sinks(&self) -> Result<()> {
        for (name, desc) in [("Arctis_Game", "Arctis 7+ Game"), ("Arctis_Chat", "Arctis 7+ Chat")] {
            // Destroy existing nodes to prevent conflicts
            let _ = Command::new("pw-cli")
                .args(["destroy", name])
                .output();

            // Create fresh native null-audio-sink adapters
            let adapter_config = format!(
                "{{ factory.name=support.null-audio-sink node.name={} node.description=\"{}\" media.class=Audio/Sink object.linger=true adapter.auto-port=true monitor.channel-volumes=true audio.position=[FL FR] }}",
                name, desc
            );
            
            Command::new("pw-cli")
                .args(["create-node", "adapter", &adapter_config])
                .output()?;
            
            thread::sleep(Duration::from_millis(200));

            // Create physical connections
            let link_l = format!("{}:monitor_FL", name);
            let link_r = format!("{}:monitor_FR", name);
            let dest_l = format!("{}:{}", self.physical_sink, self.left_target);
            let dest_r = format!("{}:{}", self.physical_sink, self.right_target);

            Command::new("pw-link").args([&link_l, &dest_l]).output()?;
            Command::new("pw-link").args([&link_r, &dest_r]).output()?;
        }

        // Set Game channel as your system default
        Command::new("pactl")
            .args(["set-default-sink", "Arctis_Game"])
            .output()?;

        Ok(())
    }

    pub fn set_volumes(&self, game_vol: f32, chat_vol: f32) -> Result<()> {
        // Convert to percentage values for pactl
        let game_pct = format!("{}%", (game_vol * 100.0).round() as i32);
        let chat_pct = format!("{}%", (chat_vol * 100.0).round() as i32);

        Command::new("pactl")
            .args(["set-sink-volume", "Arctis_Game", &game_pct])
            .output()?;

        Command::new("pactl")
            .args(["set-sink-volume", "Arctis_Chat", &chat_pct])
            .output()?;

        Ok(())
    }
}