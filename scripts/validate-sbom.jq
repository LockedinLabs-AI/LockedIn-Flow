def require($condition; $message):
  if $condition then . else error($message) end;

. as $bom
| require(.bomFormat == "CycloneDX"; "bomFormat must be CycloneDX")
| require(.specVersion == "1.6"; "specVersion must be 1.6")
| require((.serialNumber // "") | (type == "string" and test("^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")); "RFC 4122 serialNumber is required for attestation")
| require(.version == 1; "SBOM version must be 1")
| require(."$schema" == "https://cyclonedx.org/schema/bom-1.6.schema.json"; "official schema URL missing")
| require((.metadata.component.type == "application") and (.metadata.component.name | length > 0); "application metadata missing")
| require((.metadata.component."bom-ref" | length) > 0; "application bom-ref missing")
| require((.metadata.component.licenses | type) == "array" and any(.metadata.component.licenses[]; .license.id == "MIT"); "application MIT license missing")
| require((.components | type) == "array" and (.components | length) > 0; "components missing")
| require(all(.components[]; .type as $type | (["framework", "library", "machine-learning-model"] | index($type)) != null); "unsupported component type")
| require(all(.components[]; (."bom-ref" | type) == "string" and (."bom-ref" | length) > 0); "component bom-ref missing")
| require(all(.components[]; (.name | type) == "string" and (.name | length) > 0); "component name missing")
| require(all(.components[]; (.licenses | type) == "array" and (.licenses | length) > 0); "component license missing")
| ([.metadata.component."bom-ref"] + [.components[]."bom-ref"]) as $refs
| require(($refs | length) == ($refs | unique | length); "bom-ref values must be unique")
| require(all(.dependencies[]; .ref as $ref | ($refs | index($ref)) != null); "dependency ref is not declared")
| require(([.dependencies[].dependsOn[]?] | all(. as $dependency | ($refs | index($dependency)) != null)); "dependsOn ref is not declared")
| [.components[] | select(.type == "machine-learning-model")] as $models
| require(($models | length) > 0; "at least one runtime model component is required")
| require(all($models[]; any(.properties[]; .name == "com.lockedinflow.component.version-status" and (.value | test("^pinned-revision-[0-9a-f]{40}$")))); "runtime model revision pin missing")
| require(all($models[]; any(.properties[]; .name == "com.lockedinflow.component.artifact-hash-status" and (.value | test("^all-[0-9]+-runtime-files-sha256-pinned-in-source$")))); "runtime model file-hash inventory missing")
| .metadata.component."bom-ref" as $rootRef
| require(any(.compositions[]; .aggregate == "incomplete" and (.assemblies | index($rootRef)) != null); "incomplete composition disclosure missing")
| require(all(.. | strings; (contains("/Users/") or contains("/private/tmp/") or startswith("file://")) | not); "local path leaked into SBOM")
| require(all(.components[].externalReferences[]?.url; startswith("https://") and (contains("?") | not) and (test("^https://[^/]*@") | not)); "external reference must be public HTTPS without credentials or query parameters")
| true
