export function linkerPrivacyFlags(platform) {
  // MSVC's CodeView record is written by the linker, not compiler path remapping.
  return platform === "win32" ? ["-C", "link-arg=/PDBALTPATH:%_PDB%"] : [];
}

// Return classifications only. Raw paths and surrounding binary contents must
// never become diagnostics in a public build log.
export function privatePathFindings(binary, prefixes) {
  const findings = [];
  for (const { scope, prefix } of prefixes) {
    if (!["home", "checkout"].includes(scope) || !prefix || prefix.length < 3)
      throw new Error("Invalid artifact privacy boundary.");
    const forms = new Set([prefix, prefix.replaceAll("\\", "/")]);
    for (const form of forms) {
      for (const encoding of ["utf8", "utf16le"]) {
        const needle = Buffer.from(form, encoding);
        const kinds = new Map();
        let position = binary.indexOf(needle);
        while (position >= 0) {
          const codeView = encoding === "utf8" && position >= 24 &&
            binary.subarray(position - 24, position - 20).equals(Buffer.from("RSDS"));
          const kind = codeView ? "debug-symbol-reference" : "source-or-data";
          kinds.set(kind, (kinds.get(kind) ?? 0) + 1);
          position = binary.indexOf(needle, position + needle.length);
        }
        for (const [kind, count] of kinds) findings.push({ scope, encoding, kind, count });
      }
    }
  }
  return findings;
}
