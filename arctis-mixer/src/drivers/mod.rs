pub enum MixerEvent {
    // A value between 0.0 (100% Chat) and 1.0 (100% Game)
    ChatMixBalance(f32),
}

pub trait HeadsetDriver: Send + Sync {
    /// Friendly name of the headset handled by this driver
    fn get_name(&self) -> &str;

    /// USB Vendor ID (SteelSeries is 0x1038)
    fn get_vendor_id(&self) -> u16;

    /// USB Product ID (or None to match by name substring)
    fn get_product_id(&self) -> Option<u16>;

    /// Check if a detected device name matches this driver
    fn matches_device_name(&self, name: &str) -> bool;

    /// Parse a raw HID packet into a standard MixerEvent
    fn parse_packet(&self, packet: &[u8]) -> Option<MixerEvent>;
}

pub mod nova7;