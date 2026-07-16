pub trait HeadsetDriver {
    fn get_name(&self) -> &str;
    fn handle_dial_event(&self, raw_data: &[u8]) -> Option<MixerEvent>;
}

pub enum MixerEvent {
    VolumeChanged(f32),
    BalanceChanged(f32),
}