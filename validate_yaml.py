#!/usr/bin/env python3
"""
Standalone YAML validation script for DMHub Draw Steel Codex import files.

Replicates all checks from the /validate Lua macro in Macros.lua and adds
additional structural checks that are easier with proper YAML parsing.

Usage:
    python validate_yaml.py file1.yaml [file2.yaml ...]

Files are resolved relative to compendium/import/ unless an absolute path
is given.

Requires: PyYAML (pip install pyyaml)
"""

import sys
import os
import re
import argparse
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(2)

# ---------------------------------------------------------------------------
# ANSI color helpers
# ---------------------------------------------------------------------------

RED = "\033[91m"
YELLOW = "\033[93m"
GREEN = "\033[92m"
BOLD = "\033[1m"
RESET = "\033[0m"


def color_error(msg: str) -> str:
    return f"{RED}{BOLD}ERROR{RESET}{RED}: {msg}{RESET}"


def color_warning(msg: str) -> str:
    return f"{YELLOW}{BOLD}WARN{RESET}{YELLOW}: {msg}{RESET}"


def color_ok(msg: str) -> str:
    return f"{GREEN}{msg}{RESET}"


# ---------------------------------------------------------------------------
# Known valid table names (mirrors g_validTableNames in Macros.lua)
# ---------------------------------------------------------------------------

VALID_TABLE_NAMES = {
    "characterOngoingEffects",
    "charConditions",
    "standardAbilities",
    "tbl_Gear",
    "MonsterGroup",
    "classes",
    "subclasses",
    "kits",
    "cultures",
    "feats",
    "Skills",
    "damageTypes",
    "characterResources",
    "complications",
    "titles",
    "races",
    "globalRuleMods",
    "customAttributes",
    "conditionRiders",
    "encounters",
    "backgrounds",
    "equipmentCategories",
    "documents",
    "careers",
    "languages",
    "Deities",
    "DeityDomains",
    "minionWithCaptain",
    "importerPowerTableEffects",
    "importerMonsterTraits",
    "VisionType",
    "parties",
    "adventureTables",
    "compendiumPermissions",
    "characteristicsTable",
    "importerAbilityEffects",
    "pdfReferences",
    "featurePrefabs",
    "creatureTemplates",
    "languageRelations",
    "importerStandardFeatures",
    "powerRolls",
    "weaponProperties",
    "currency",
    "characterTypes",
    "cultureAspects",
    "nameGenerators",
}

VALID_TABLE_NAMES_LOWER = {n.lower(): n for n in VALID_TABLE_NAMES}

UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


# ---------------------------------------------------------------------------
# Result collector
# ---------------------------------------------------------------------------

class ValidationResult:
    def __init__(self, filename: str):
        self.filename = filename
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def err(self, msg: str):
        self.errors.append(f"[{self.filename}] {msg}")

    def warn(self, msg: str):
        self.warnings.append(f"[{self.filename}] {msg}")


# ---------------------------------------------------------------------------
# Text-level checks (mirrors ValidateYamlText in Macros.lua)
# ---------------------------------------------------------------------------

def check_non_ascii(text: str, result: ValidationResult):
    for i, line in enumerate(text.split("\n"), start=1):
        if any(ord(ch) > 127 for ch in line):
            result.err(f"Non-ASCII characters found on line {i} (files must be ASCII-only)")
            return  # report only the first occurrence


def check_table_names(text: str, result: ValidationResult):
    for m in re.finditer(r"_table:\s*(\w+)", text):
        table_name = m.group(1)
        if table_name not in VALID_TABLE_NAMES:
            lower = table_name.lower()
            suggestion = VALID_TABLE_NAMES_LOWER.get(lower)
            if suggestion:
                result.err(
                    f"Invalid table name '{table_name}' - did you mean "
                    f"'{suggestion}'? (table names are case-sensitive)"
                )
            else:
                result.err(
                    f"Unknown table name '{table_name}' - check against known table names"
                )


def check_ongoing_effect(text: str, result: ValidationResult):
    if "CharacterOngoingEffect" not in text:
        return
    if "iconid:" not in text:
        result.err(
            "CharacterOngoingEffect found but no 'iconid' field -- "
            "iconid is required (crashes if missing)"
        )
    else:
        if re.search(r"iconid:\s*$", text, re.MULTILINE):
            result.err(
                "CharacterOngoingEffect has empty iconid -- "
                "iconid is required (crashes if missing)"
            )
        if re.search(r"iconid:\s*(?:null|nil)", text):
            result.err(
                "CharacterOngoingEffect has null/nil iconid -- "
                "iconid is required (crashes if missing)"
            )
    if "display:" not in text:
        result.err(
            "CharacterOngoingEffect found but no 'display' table -- display is required"
        )


def check_condition(text: str, result: ValidationResult):
    if not re.search(r"__typeName:\s*CharacterCondition", text):
        return
    if "iconid:" not in text:
        result.err("CharacterCondition found but no 'iconid' field -- iconid is required")
    if "display:" not in text:
        result.err("CharacterCondition found but no 'display' table -- display is required")
    if "domains:" not in text:
        result.err("CharacterCondition found but no 'domains' field -- domains is required")


def check_feature_choice(text: str, result: ValidationResult):
    if "CharacterFeatureChoice" not in text:
        return
    if "allowDuplicateChoices" not in text:
        result.err(
            "CharacterFeatureChoice found but 'allowDuplicateChoices' is missing -- "
            "this field is REQUIRED (crashes if omitted)"
        )


def check_goblinscript_booleans(text: str, result: ValidationResult):
    if re.search(r'activationCondition:\s*"true"', text):
        result.err(
            'activationCondition: "true" found -- GoblinScript does not recognize '
            '"true", use "1" instead'
        )
    if re.search(r'activationCondition:\s*"false"', text):
        result.err(
            'activationCondition: "false" found -- GoblinScript does not recognize '
            '"false", use "0" instead'
        )


def check_invalid_duration(text: str, result: ValidationResult):
    if "ActivatedAbilityApplyOngoingEffectBehavior" not in text:
        return
    if re.search(r'duration:\s*"?nextturn"?', text):
        result.err(
            'duration: "nextturn" is invalid for ApplyOngoingEffectBehavior -- '
            'use "end_of_next_turn" instead (nextturn is aura-only)'
        )


def check_stability_attribute(text: str, result: ValidationResult):
    if re.search(r"attribute:\s*stability", text):
        result.warn(
            "attribute: stability found -- 'stability' is not a valid attribute ID, "
            "use 'forcedmoveresistance' instead"
        )


def check_empty_roll(text: str, result: ValidationResult):
    if "ActivatedAbilityPowerRollBehavior" in text and "roll: ''" in text:
        result.err(
            "ActivatedAbilityPowerRollBehavior has empty roll: '' -- "
            "must be a dice formula like '2d10 + Might or Agility'"
        )


def check_target_type_enemies(text: str, result: ValidationResult):
    if re.search(r"targetType:\s*enemies", text):
        result.err(
            "targetType: enemies is not valid -- "
            "use targetType: target with targetAllegiance: enemy"
        )


def check_missing_table(text: str, is_bundle: bool, result: ValidationResult):
    """Check that non-bundle files with top-level __typeName also have _table."""
    if is_bundle:
        return
    # Check for top-level __typeName (at start of file or after _table line)
    if re.search(r"(?:^|\n)__typeName:", text):
        # info: means monster (doesn't need _table)
        if re.search(r"(?:^|\n)info:", text):
            return
        if not re.search(r"(?:^|\n)_table:", text):
            result.err(
                "Entry has __typeName but no '_table' field -- "
                "table entries require '_table: tableName' to specify the target table"
            )


def check_mixed_entry_and_bundle(text: str, is_bundle: bool, result: ValidationResult):
    """Check that a file doesn't have both __typeName and _bundle at top level."""
    if not is_bundle:
        return
    if re.search(r"(?:^|\n)__typeName:", text):
        result.err(
            "File has both '_bundle' and top-level '__typeName' -- "
            "a file must be either a single entry OR a bundle manifest, not both. "
            "Split the bundle items into separate files and use _include."
        )


def check_missing_id(text: str, is_bundle: bool, result: ValidationResult):
    if is_bundle:
        return
    if "__typeName:" in text:
        if not re.search(r"(?:^|\n)id:", text):
            result.warn(
                "Entry has __typeName but no top-level 'id' field -- most types require an id"
            )


def check_missing_guid_feature(text: str, result: ValidationResult):
    if re.search(r"__typeName:\s*CharacterFeature", text):
        if "guid:" not in text:
            result.warn(
                "CharacterFeature found but no 'guid' field anywhere -- "
                "guid is required on features"
            )


def check_modifier_behavior(text: str, result: ValidationResult):
    if re.search(r"__typeName:\s*CharacterModifier", text):
        if "behavior:" not in text:
            result.warn(
                "CharacterModifier found but no 'behavior' field -- "
                "behavior is required on modifiers"
            )


def check_class_levels(text: str, result: ValidationResult):
    if re.search(r"__typeName:\s*Class", text) and re.search(r"_table:\s*classes", text):
        if "levels:" not in text:
            result.err("Class entry found but no 'levels' field -- levels is required on classes")


def check_kit_type(text: str, result: ValidationResult):
    # Text-level Kit check disabled -- handled in YAML-parsed checks per-item
    pass


def check_monster_properties(text: str, result: ValidationResult):
    if re.search(r"(?:^|\n)info:", text):
        if "properties:" not in text:
            result.warn(
                "Monster entry found (has 'info') but no 'properties' field inside info"
            )


def check_duplicate_ids(text: str, result: ValidationResult):
    ids: dict[str, int] = {}
    first_match = re.match(r"^id:\s*([0-9a-fA-F\-]+)", text)
    if first_match:
        ids[first_match.group(1)] = ids.get(first_match.group(1), 0) + 1
    for m in re.finditer(r"\nid:\s*([0-9a-fA-F\-]+)", text):
        ids[m.group(1)] = ids.get(m.group(1), 0) + 1
    for id_val, count in ids.items():
        if count > 1:
            result.err(f"Duplicate id '{id_val}' found in the same file")


def check_empty_id_guid(text: str, result: ValidationResult):
    if re.search(r"(?:^|\n)id:\s*(?:\n|$)", text):
        result.err("Empty 'id' field found -- id must be a non-empty string")
    if re.search(r"\nguid:\s*(?:\n|$)", text):
        result.err("Empty 'guid' field found -- guid must be a non-empty string")


def check_missing_modifier_info(text: str, result: ValidationResult):
    if re.search(r"__typeName:\s*CharacterComplication", text):
        if "modifierInfo:" not in text:
            result.warn(
                "CharacterComplication found but no 'modifierInfo' field -- modifierInfo is required"
            )
    if re.search(r"__typeName:\s*Title", text):
        if "modifierInfo:" not in text:
            result.warn(
                "Title found but no 'modifierInfo' field -- modifierInfo is required"
            )
    if re.search(r"__typeName:\s*Race", text) and re.search(r"_table:\s*races", text):
        if "modifierInfo:" not in text:
            result.warn(
                "Race (ancestry) found but no 'modifierInfo' field -- modifierInfo is required"
            )


def check_equipment_category(text: str, result: ValidationResult):
    if re.search(r"__typeName:\s*(?:equipment|weapon|armor)", text):
        if re.search(r"_table:\s*tbl_Gear", text):
            if "equipmentCategory:" not in text:
                result.warn("Equipment entry found but no 'equipmentCategory' field")


def check_bundle_includes(text: str, is_bundle: bool, base_dir: Path, result: ValidationResult):
    if not is_bundle:
        return
    for m in re.finditer(r"_include:\s*([\w.\-_/]+)", text):
        include_file = m.group(1)
        include_path = base_dir / include_file
        if not include_path.exists():
            result.err(f"_include references '{include_file}' but file not found")


def run_text_checks(text: str, filename: str, base_dir: Path) -> ValidationResult:
    """Run all text-level (regex-based) checks mirroring the Lua validator."""
    result = ValidationResult(filename)
    is_bundle = text.startswith("_bundle:") or "\n_bundle:" in text

    check_non_ascii(text, result)
    check_table_names(text, result)
    check_ongoing_effect(text, result)
    check_condition(text, result)
    check_feature_choice(text, result)
    check_goblinscript_booleans(text, result)
    check_invalid_duration(text, result)
    check_stability_attribute(text, result)
    check_empty_roll(text, result)
    check_target_type_enemies(text, result)
    check_missing_table(text, is_bundle, result)
    check_mixed_entry_and_bundle(text, is_bundle, result)
    check_missing_id(text, is_bundle, result)
    check_missing_guid_feature(text, result)
    check_modifier_behavior(text, result)
    check_class_levels(text, result)
    check_kit_type(text, result)
    check_monster_properties(text, result)
    check_duplicate_ids(text, result)
    check_empty_id_guid(text, result)
    check_missing_modifier_info(text, result)
    check_equipment_category(text, result)
    check_bundle_includes(text, is_bundle, base_dir, result)

    return result


# ---------------------------------------------------------------------------
# YAML-level (structural) checks -- Python-only additions
# ---------------------------------------------------------------------------

def is_uuid(value) -> bool:
    return isinstance(value, str) and bool(UUID_RE.match(value))


def walk_nodes(data, path="root"):
    """Yield (path_string, node) for every dict in the tree."""
    if isinstance(data, dict):
        yield path, data
        for key, val in data.items():
            yield from walk_nodes(val, f"{path}.{key}")
    elif isinstance(data, list):
        for i, item in enumerate(data):
            yield from walk_nodes(item, f"{path}[{i}]")


def collect_all_guids(data) -> set[str]:
    """Collect every 'id' and 'guid' value in the tree."""
    guids: set[str] = set()
    for _, node in walk_nodes(data):
        for field in ("id", "guid"):
            val = node.get(field)
            if isinstance(val, str) and val:
                guids.add(val)
    return guids


def collect_ongoing_effect_ids(data) -> set[str]:
    """Collect ids of CharacterOngoingEffect entries in bundle data."""
    ids: set[str] = set()
    for _, node in walk_nodes(data):
        if node.get("__typeName") == "CharacterOngoingEffect":
            eid = node.get("id")
            if isinstance(eid, str) and eid:
                ids.add(eid)
    return ids


def check_modifier_sourceguid(data, result: ValidationResult):
    """Every CharacterModifier.sourceguid should match its parent's guid."""
    for path, node in walk_nodes(data):
        modifiers = node.get("modifiers")
        if not isinstance(modifiers, list):
            continue
        parent_guid = node.get("guid")
        if not parent_guid:
            continue
        for i, mod in enumerate(modifiers):
            if not isinstance(mod, dict):
                continue
            if mod.get("__typeName") != "CharacterModifier":
                continue
            sg = mod.get("sourceguid")
            if sg and sg != parent_guid:
                result.warn(
                    f"CharacterModifier at {path}.modifiers[{i}] has "
                    f"sourceguid '{sg}' which does not match parent guid '{parent_guid}'"
                )


def check_domains_parent_key(data, result: ValidationResult):
    """Domains should include the correct parent type key."""
    type_to_domain_prefix = {
        "CharacterCondition": "CharacterCondition:",
        "CharacterOngoingEffect": "CharacterOngoingEffect:",
    }
    for path, node in walk_nodes(data):
        tn = node.get("__typeName")
        if tn not in type_to_domain_prefix:
            continue
        prefix = type_to_domain_prefix[tn]
        nid = node.get("id")
        if not nid:
            continue
        domains = node.get("domains")
        if not isinstance(domains, dict):
            continue
        expected_key = f"{prefix}{nid}"
        if expected_key not in domains:
            result.warn(
                f"{tn} at {path} has id '{nid}' but domains does not contain "
                f"'{expected_key}'"
            )


def check_uuid_format(data, result: ValidationResult):
    """Validate that id and guid fields use proper UUID format."""
    for path, node in walk_nodes(data):
        for field in ("id", "guid"):
            val = node.get(field)
            if val is None or val is False or val == "":
                continue
            if isinstance(val, str):
                # Only warn if it looks like it's trying to be a UUID (has dashes)
                # but isn't valid, or is at a top-level entry that should be UUID.
                if "-" in val and not is_uuid(val):
                    result.warn(
                        f"Field '{field}' at {path} has value '{val}' which "
                        f"looks like a malformed UUID (expected 8-4-4-4-12 hex)"
                    )


def check_ongoing_effect_references(data, result: ValidationResult):
    """Check that ongoingEffect UUIDs in behaviors reference entries in the bundle.

    Only flags custom effects defined in the same bundle that are referenced
    incorrectly. References to UUIDs not present in the bundle at all are
    assumed to be built-in engine effects and silently skipped.
    """
    effect_ids = collect_ongoing_effect_ids(data)
    if not effect_ids:
        return  # no custom effects in this bundle; nothing to cross-reference

    all_guids = collect_all_guids(data)

    for path, node in walk_nodes(data):
        tn = node.get("__typeName")
        if tn != "ActivatedAbilityApplyOngoingEffectBehavior":
            continue
        oe_ref = node.get("ongoingEffect")
        if not isinstance(oe_ref, str) or not oe_ref:
            continue
        if not is_uuid(oe_ref):
            continue
        # If the UUID appears somewhere in this bundle (e.g. as an id/guid)
        # but NOT as a CharacterOngoingEffect id, it is likely a mis-reference.
        if oe_ref not in effect_ids and oe_ref in all_guids:
            result.warn(
                f"ApplyOngoingEffectBehavior at {path} references ongoingEffect "
                f"'{oe_ref}' which exists in the bundle but is not a "
                f"CharacterOngoingEffect id"
            )


def check_subclass_primary_class(data, result: ValidationResult):
    """Verify subclass primaryClassId matches a class in the bundle."""
    # Collect class ids
    class_ids: set[str] = set()
    subclass_refs: list[tuple[str, str]] = []

    for path, node in walk_nodes(data):
        tn = node.get("__typeName")
        if tn == "Class":
            nid = node.get("id")
            if nid and not node.get("isSubclass"):
                class_ids.add(nid)
            pcid = node.get("primaryClassId")
            if node.get("isSubclass") and pcid:
                subclass_refs.append((path, pcid))

    if not class_ids or not subclass_refs:
        return

    for path, pcid in subclass_refs:
        if pcid not in class_ids:
            # Only warn -- the parent class may be a built-in
            result.warn(
                f"Subclass at {path} has primaryClassId '{pcid}' which "
                f"does not match any Class id in this bundle (may be a built-in class)"
            )


def check_feature_choice_options(data, result: ValidationResult):
    """CharacterFeatureChoice options must be arrays with >= 1 entry."""
    for path, node in walk_nodes(data):
        if node.get("__typeName") != "CharacterFeatureChoice":
            continue
        options = node.get("options")
        if options is None:
            result.err(
                f"CharacterFeatureChoice at {path} is missing 'options' field"
            )
        elif not isinstance(options, list):
            result.err(
                f"CharacterFeatureChoice at {path} has 'options' that is not an array"
            )
        elif len(options) == 0:
            result.warn(
                f"CharacterFeatureChoice at {path} has empty 'options' array"
            )

        # Also re-check allowDuplicateChoices at the structural level
        if "allowDuplicateChoices" not in node:
            result.err(
                f"CharacterFeatureChoice at {path} is missing 'allowDuplicateChoices' "
                f"(crashes if omitted)"
            )


def run_yaml_checks(data, result: ValidationResult):
    """Run all YAML-level structural checks (Python-only additions)."""
    if data is None:
        return

    check_modifier_sourceguid(data, result)
    check_domains_parent_key(data, result)
    check_uuid_format(data, result)
    check_ongoing_effect_references(data, result)
    check_subclass_primary_class(data, result)
    check_feature_choice_options(data, result)
    check_kit_type_yaml(data, result)


def check_kit_type_yaml(data, result: ValidationResult):
    """Check that Kit entries have a 'type' field (per-item, not whole-file)."""
    items = []
    if isinstance(data, dict):
        if "_bundle" in data and isinstance(data["_bundle"], list):
            items = data["_bundle"]
        else:
            items = [data]
    for item in items:
        if isinstance(item, dict) and item.get("__typeName") == "Kit":
            if not item.get("type"):
                name = item.get("name", "?")
                result.warn(
                    f"Kit '{name}' is missing 'type' field -- "
                    f"type is required (e.g. martial, caster)"
                )


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def validate_file(filepath: Path, base_dir: Path) -> ValidationResult:
    """Validate a single YAML file with both text-level and structural checks."""
    filename = filepath.name

    # Read raw text for text-level checks
    try:
        text = filepath.read_text(encoding="utf-8")
    except Exception as e:
        r = ValidationResult(filename)
        r.err(f"Could not read file: {e}")
        return r

    # Text-level checks
    result = run_text_checks(text, filename, base_dir)

    # Parse YAML for structural checks
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as e:
        result.err(f"YAML parse error: {e}")
        return result

    if data is not None:
        run_yaml_checks(data, result)

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Validate DMHub YAML import files."
    )
    parser.add_argument(
        "files",
        nargs="+",
        help="YAML filenames (resolved relative to compendium/import/ unless absolute)",
    )
    parser.add_argument(
        "--base-dir",
        default=None,
        help="Base directory for import files (default: compendium/import/ relative to script)",
    )
    args = parser.parse_args()

    # Resolve base directory
    script_dir = Path(__file__).resolve().parent
    if args.base_dir:
        base_dir = Path(args.base_dir).resolve()
    else:
        base_dir = script_dir / "compendium" / "import"

    total_errors = 0
    total_warnings = 0
    files_checked = 0

    for filename in args.files:
        fpath = Path(filename)
        if not fpath.is_absolute():
            fpath = base_dir / fpath
        fpath = fpath.resolve()

        if not fpath.exists():
            print(color_error(f"[{filename}] File not found: {fpath}"))
            total_errors += 1
            continue

        result = validate_file(fpath, base_dir)
        files_checked += 1

        for e in result.errors:
            print(color_error(e))
        for w in result.warnings:
            print(color_warning(w))

        if not result.errors and not result.warnings:
            print(color_ok(f"[{result.filename}] OK"))

        total_errors += len(result.errors)
        total_warnings += len(result.warnings)

    # Summary
    print()
    if total_errors == 0 and total_warnings == 0:
        print(color_ok(f"All {files_checked} file(s) passed validation."))
    else:
        parts = []
        if total_errors:
            parts.append(f"{RED}{BOLD}{total_errors} error(s){RESET}")
        if total_warnings:
            parts.append(f"{YELLOW}{BOLD}{total_warnings} warning(s){RESET}")
        print(f"Summary: {', '.join(parts)} across {files_checked} file(s).")

    sys.exit(1 if total_errors > 0 else 0)


if __name__ == "__main__":
    main()
