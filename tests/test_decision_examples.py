import importlib.util
import json
import sys
from dataclasses import replace
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "cortexos_automation_scripts" / "scripts" / "build_decision_examples.py"


def load_module():
    spec = importlib.util.spec_from_file_location("build_decision_examples", MODULE_PATH)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_initial_decision_examples_pass_quality_gate():
    module = load_module()
    payload = module.run_check()
    assert payload["status"] == "ok"
    assert payload["count"] == 10
    assert payload["errors"] == {}


def test_decision_example_rendering_has_seo_and_signature_sections():
    module = load_module()
    example = module.DECISION_EXAMPLES[0]
    rendered = module.render_example(example)
    assert f'title: "{example.title}"' in rendered
    assert f'canonical_path: "{example.canonical_path}"' in rendered
    assert "## Messy input" in rendered
    assert "## Signals detected" in rendered
    assert "## Ignored noise" in rendered
    assert "## 3 priorities" in rendered
    assert rendered.count("Why:") == 3
    assert rendered.count("Action:") == 3


def test_decision_example_gate_rejects_sensitive_content():
    module = load_module()
    example = replace(
        module.DECISION_EXAMPLES[0],
        messy_input="Email founder@example.com with the confidential password before launch.",
    )
    errors = module.validate_example(example)
    assert any("sensitive pattern detected" in error for error in errors)


def test_decision_example_writer_outputs_archive_and_manifest(tmp_path):
    module = load_module()
    payload = module.write_outputs(tmp_path)
    assert payload["status"] == "ok"
    assert Path(payload["index"]).exists()
    manifest_path = Path(payload["manifest"])
    assert manifest_path.exists()

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["count"] == 10
    assert len(manifest["examples"]) == 10
    assert manifest["examples"][0]["priority_count"] == 3
