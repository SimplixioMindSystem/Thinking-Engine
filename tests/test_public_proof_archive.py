import importlib.util
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "cortexos_automation_scripts" / "scripts" / "build_public_proof_archive.py"


def load_module():
    spec = importlib.util.spec_from_file_location("build_public_proof_archive", MODULE_PATH)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_public_proof_archive_writes_index_and_manifest(tmp_path):
    module = load_module()
    payload = module.build_archive(tmp_path)
    assert payload["status"] == "ok"
    assert payload["proof_surface_count"] == 5

    index_text = Path(payload["index"]).read_text(encoding="utf-8")
    assert "messy input -> filtered signal -> 3 priorities -> why -> next action" in index_text
    assert "No autopublish" in index_text

    manifest = json.loads(Path(payload["manifest"]).read_text(encoding="utf-8"))
    assert manifest["publishing_rules"]["manual_approval_required"] is True
    assert manifest["publishing_rules"]["private_material_allowed"] is False


def test_public_proof_archive_features_desire_loop_examples():
    module = load_module()
    examples = module.top_decision_examples(module.load_decision_examples())
    slugs = {example["slug"] for example in examples}
    assert "how-to-prioritize-startup-ideas" in slugs
    assert "how-to-turn-github-issues-into-priorities" in slugs
    assert "how-to-review-your-week-as-a-solo-founder" in slugs
