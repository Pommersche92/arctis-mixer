mod drivers;
mod pipewire_mgr;

use drivers::{nova7::Nova7Driver, HeadsetDriver, MixerEvent};
use hidapi::{HidApi, HidDevice};
use pipewire_mgr::PipewireManager;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

fn find_and_open_device(api: &HidApi, driver: &dyn HeadsetDriver) -> Option<HidDevice> {
    for device_info in api.device_list() {
        if device_info.vendor_id() == driver.get_vendor_id() {
            let product_matches = match driver.get_product_id() {
                Some(pid) => device_info.product_id() == pid,
                None => {
                    if let Some(prod_str) = device_info.product_string() {
                        driver.matches_device_name(prod_str)
                    } else {
                        false
                    }
                }
            };

            if product_matches {
                // Try opening the device interface
                if let Ok(dev) = device_info.open_device(api) {
                    return Some(dev);
                }
            }
        }
    }
    None
}

fn main() -> anyhow::Result<()> {
    println!("--- SteelSeries ChatMix Universal Daemon (Rust) ---");

    // 1. Initialize PipeWire Audio Infrastructure
    let pw = Arc::new(PipewireManager::new()?);
    pw.setup_sinks()?;
    println!("PipeWire Virtual Sinks Created Successfully.");

    // 2. Select Driver (Easily configurable in the future)
    let driver: Box<dyn HeadsetDriver> = Box::new(Nova7Driver::new());
    println!("Loaded Driver: {}", driver.get_name());

    // 3. Keep-alive loop to reconnect physical device if unplugged/rebooted
    let api = HidApi::new()?;
    loop {
        println!("Searching for physical USB dial connection...");
        if let Some(device) = find_and_open_device(&api, &*driver) {
            println!("Connected to physical headset dial interface!");

            let mut buf = [0u8; 64];
            loop {
                // Read USB interrupt transfers
                match device.read_timeout(&mut buf, 1000) {
                    Ok(bytes_read) => {
                        if bytes_read > 0 {
                            if let Some(MixerEvent::ChatMixBalance(balance)) =
                                driver.parse_packet(&buf[..bytes_read])
                            {
                                // Linear audio balance mapping
                                // Left side of dial favors Chat, right side favors Game
                                let game_volume = balance.min(0.5) * 2.0;
                                let chat_volume = (1.0 - balance).min(0.5) * 2.0;

                                println!(
                                    "Dial Balance: {:.1}% | Game: {:.1}% | Chat: {:.1}%",
                                    balance * 100.0,
                                    game_volume * 100.0,
                                    chat_volume * 100.0
                                );

                                if let Err(e) = pw.set_volumes(game_volume, chat_volume) {
                                    eprintln!("Failed to apply volume adjustment: {}", e);
                                }
                            }
                        }
                    }
                    Err(e) => {
                        eprintln!("USB Read error (headset unplugged?): {}", e);
                        break; // Drop inner loop and try to reconnect
                    }
                }
            }
        }

        thread::sleep(Duration::from_secs(3));
    }
}
