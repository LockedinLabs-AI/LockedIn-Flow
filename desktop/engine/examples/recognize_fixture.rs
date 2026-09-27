//! Developer-only offline inference check. Reports comparison, never transcript content.
//! Usage: cargo run -p lockedin-flow-engine --example recognize_fixture -- MODEL WAV EXPECTED
use lockedin_flow_engine::speech::SpeechEngine;
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 4 {
        return Err("Expected model, synthetic WAV, and expected-text file paths.".into());
    }
    let mut wav = hound::WavReader::open(&args[2])?;
    let spec = wav.spec();
    if spec.channels != 1 || spec.sample_rate != 16_000 || spec.bits_per_sample != 16 {
        return Err("Use a 16 kHz mono signed 16-bit synthetic WAV.".into());
    }
    let samples = wav
        .samples::<i16>()
        .map(|sample| sample.map(|v| v as f32 / 32768.0))
        .collect::<Result<Vec<_>, _>>()?;
    let engine = SpeechEngine::load(Path::new(&args[1]))?;
    let actual = engine.transcribe(&samples)?;
    let expected = std::fs::read_to_string(&args[3])?;
    let words = |value: &str| {
        value
            .to_lowercase()
            .split(|c: char| !c.is_alphanumeric())
            .filter(|v| !v.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>()
    };
    if words(&actual) != words(&expected) {
        return Err("Synthetic speech comparison did not match.".into());
    }
    println!(
        "Synthetic offline speech comparison passed ({} words).",
        words(&actual).len()
    );
    Ok(())
}
