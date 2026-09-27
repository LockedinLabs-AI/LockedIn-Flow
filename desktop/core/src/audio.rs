//! Bounded capture storage. A device error preserves the samples already captured.
use crate::MAX_RECORDING_SECONDS;
use zeroize::Zeroize;

pub struct CaptureBuffer {
    samples: Vec<f32>,
    limit: usize,
    pub interrupted: bool,
    pub full: bool,
    pub peak: f32,
}

impl CaptureBuffer {
    pub fn new(rate: u32) -> Result<Self, &'static str> {
        if !(8_000..=192_000).contains(&rate) {
            return Err("This microphone sample rate is not supported.");
        }
        let limit = rate as usize * MAX_RECORDING_SECONDS;
        let mut samples = Vec::new();
        samples
            .try_reserve_exact(limit)
            .map_err(|_| "Not enough memory to start recording.")?;
        Ok(Self {
            samples,
            limit,
            interrupted: false,
            full: false,
            peak: 0.0,
        })
    }

    /// No allocation on the capture callback. Invalid frames stop capture, not silently disappear.
    pub fn push_interleaved<T>(&mut self, input: &[T], channels: usize, convert: impl Fn(T) -> f32)
    where
        T: Copy,
    {
        if self.interrupted || self.full {
            return;
        }
        if channels == 0 || channels > 32 || !input.len().is_multiple_of(channels) {
            self.interrupted = true;
            return;
        }
        self.peak = 0.0;
        for frame in input.chunks_exact(channels) {
            if self.samples.len() == self.limit {
                self.full = true;
                break;
            }
            let mut mono = 0.0;
            for sample in frame {
                let value = convert(*sample);
                if !value.is_finite() {
                    self.interrupted = true;
                    return;
                }
                mono += value.clamp(-1.0, 1.0) / channels as f32;
            }
            self.peak = self.peak.max(mono.abs());
            self.samples.push(mono);
        }
        self.full |= self.samples.len() == self.limit;
    }

    pub fn len(&self) -> usize {
        self.samples.len()
    }
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }
    pub fn take(&mut self) -> Vec<f32> {
        std::mem::take(&mut self.samples)
    }
}

impl Drop for CaptureBuffer {
    fn drop(&mut self) {
        self.samples.zeroize();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn downmix_and_invalid_frames_preserve_captured_audio() {
        let mut buffer = CaptureBuffer::new(16_000).unwrap();
        buffer.push_interleaved(&[1.0, -1.0, 0.25, 0.75], 2, |v| v);
        buffer.push_interleaved(&[f32::NAN], 1, |v| v);
        buffer.push_interleaved(&[0.9], 1, |v| v);
        assert!(buffer.interrupted);
        assert_eq!(buffer.take(), [0.0, 0.5]);
    }

    #[test]
    fn duration_limit_is_enforced_without_overrun() {
        let mut buffer = CaptureBuffer::new(8_000).unwrap();
        let frame = vec![0.1; 8_000];
        for _ in 0..MAX_RECORDING_SECONDS + 5 {
            buffer.push_interleaved(&frame, 1, |v| v);
        }
        assert_eq!(buffer.len(), 8_000 * MAX_RECORDING_SECONDS);
        assert!(buffer.full);
    }

    #[test]
    fn channels_rates_and_nonfinite_values_are_validated() {
        assert!(CaptureBuffer::new(0).is_err());
        assert!(CaptureBuffer::new(u32::MAX).is_err());
        for channels in [0, 2, 33] {
            let mut buffer = CaptureBuffer::new(16_000).unwrap();
            buffer.push_interleaved(&[0.1], channels, |v| v);
            assert!(buffer.interrupted);
        }
    }
}
