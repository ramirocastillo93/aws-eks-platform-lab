import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from terraform_plan_review import plan_fingerprints_from_json


def sample_plan():
    return {
        "timestamp": "2026-10-22T00:00:00Z",
        "prior_state": {"serial": 1},
        "resource_changes": [
            {
                "address": "aws_eks_cluster.lab",
                "mode": "managed",
                "type": "aws_eks_cluster",
                "change": {
                    "actions": ["create"],
                    "before": None,
                    "after": {"public_access_cidrs": ["198.51.100.7/32"]},
                    "after_unknown": {"endpoint": True},
                    "after_sensitive": {"public_access_cidrs": True},
                },
            }
        ],
        "output_changes": {"cluster_name": {"actions": ["create"], "after": "lab"}},
        "resource_drift": [],
        "deferred_changes": [],
        "checks": [],
    }


class PlanFingerprintsTest(unittest.TestCase):
    def test_ignores_timestamp_and_prior_state_representation(self):
        original = sample_plan()
        refreshed = sample_plan()
        refreshed["timestamp"] = "2026-10-22T00:05:00Z"
        refreshed["prior_state"] = {"serial": 2, "lineage": "different"}

        self.assertEqual(
            plan_fingerprints_from_json(original),
            plan_fingerprints_from_json(refreshed),
        )

    def test_sensitive_resource_value_changes_fingerprint_without_logging_value(self):
        original = plan_fingerprints_from_json(sample_plan())
        changed_plan = sample_plan()
        changed_plan["resource_changes"][0]["change"]["after"][
            "public_access_cidrs"
        ] = ["203.0.113.8/32"]
        changed = plan_fingerprints_from_json(changed_plan)

        self.assertNotEqual(original["resource_changes"], changed["resource_changes"])

    def test_ignores_resource_order_but_detects_action_changes(self):
        original = sample_plan()
        reversed_plan = sample_plan()
        original["resource_changes"].append(
            {"address": "aws_iam_role.lab", "change": {"actions": ["create"]}}
        )
        reversed_plan = copy.deepcopy(original)
        reversed_plan["resource_changes"] = list(reversed(reversed_plan["resource_changes"]))
        self.assertEqual(
            plan_fingerprints_from_json(original),
            plan_fingerprints_from_json(reversed_plan),
        )

        reversed_plan["resource_changes"][0]["change"]["actions"] = ["delete"]
        self.assertNotEqual(
            plan_fingerprints_from_json(original)["resource_changes"],
            plan_fingerprints_from_json(reversed_plan)["resource_changes"],
        )

    def test_preserves_replacement_action_order(self):
        delete_then_create = sample_plan()
        create_then_delete = sample_plan()
        delete_then_create["resource_changes"][0]["change"]["actions"] = [
            "delete",
            "create",
        ]
        create_then_delete["resource_changes"][0]["change"]["actions"] = [
            "create",
            "delete",
        ]

        self.assertNotEqual(
            plan_fingerprints_from_json(delete_then_create)["resource_changes"],
            plan_fingerprints_from_json(create_then_delete)["resource_changes"],
        )

    def test_output_change_is_included(self):
        original = plan_fingerprints_from_json(sample_plan())
        changed_plan = sample_plan()
        changed_plan["output_changes"]["cluster_name"]["after"] = "different"

        self.assertNotEqual(
            original["output_changes"],
            plan_fingerprints_from_json(changed_plan)["output_changes"],
        )


if __name__ == "__main__":
    unittest.main()
