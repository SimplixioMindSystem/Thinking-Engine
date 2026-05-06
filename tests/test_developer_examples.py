import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEMO_PATH = ROOT / "examples" / "simplixio_signal_demo.py"


def load_demo_module():
    spec = importlib.util.spec_from_file_location("simplixio_signal_demo", DEMO_PATH)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_demo_uses_public_safe_sample_signals():
    demo = load_demo_module()
    blocked_terms = {"secret", "token", "password", "client", "confidential", "private"}
    for signal in demo.DEMO_SIGNALS:
        text = " ".join(
            [
                signal.text,
                signal.source,
                signal.source_id,
                signal.context,
                signal.project,
                " ".join(signal.tags),
                signal.signal_type_hint,
            ]
        ).lower()
        assert not any(term in text for term in blocked_terms)


def test_dry_run_today_shows_signature_output():
    demo = load_demo_module()
    priorities = demo.DRY_RUN_TODAY["priorities"]
    assert len(priorities) == 3
    for priority in priorities:
        assert priority["title"]
        assert priority["why"]
        assert priority["action"]


def test_demo_defaults_to_dry_run():
    demo = load_demo_module()
    args = demo.parse_args([])
    assert args.live is False
    assert args.dry_run is False
    assert args.base_url == "http://127.0.0.1:8420"
