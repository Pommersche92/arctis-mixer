use super::{HeadsetDriver, MixerEvent};

pub struct Nova7Driver;

impl Nova7Driver {
    pub fn new() -> Self {
        Self
    }
}

impl HeadsetDriver for Nova7Driver {
    fn get_name(&self) -> &str {
        "SteelSeries Arctis Nova 7"
    }

    fn get_vendor_id(&self) -> u16 {
        0x1038 // SteelSeries Vendor ID
    }

    fn get_product_id(&self) -> Option<u16> {
        // We match dynamically via name to support WoW and standard variants cleanly
        None
    }

    fn matches_device_name(&self, name: &str) -> bool {
        let name_lower = name.to_lowercase();
        name_lower.contains("arctis nova 7") || name_lower.contains("wow_edition")
    }

    fn parse_packet(&self, packet: &[u8]) -> Option<MixerEvent> {
        // Ensure the packet is large enough to inspect
        if packet.len() < 3 {
            return None;
        }

        // The Nova 7 reports ChatMix dial bytes.
        // We inspect packet signatures to extract the dial state.
        if packet[0] == 0x06 && packet[1] == 0x12 {
            let raw_value = packet[2] as f32; // Typically 0 to 100 or 0 to 255

            // Map the raw value to a 0.0 -> 1.0 balance range
            // (0.0 = Pure Chat, 0.5 = Centered 50/50, 1.0 = Pure Game)
            let balance = raw_value / 255.0;
            return Some(MixerEvent::ChatMixBalance(balance));
        }

        None
    }
}
