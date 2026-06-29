package cape_test

import rego.v1
import data.cape

test_allow_write_to_tributary_resource if {
    cape.allow with input as {
        "user": {"id": 1},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/eng/raw-uploads/file.csv"
        }
    } with data.user_tributaries as [
        {"user_id": 1, "tributary_id": 1},
        {"user_id": 1, "tributary_id": 2},
        {"user_id": 2, "tributary_id": 2}
    ] with data.resources as [
        {
            "id": 1,
            "tributary_id": 1,
            "resource_identifier": "s3://test-bucket/eng/raw-uploads/",
            "access_pattern": "write"
        },
        {
            "id": 2,
            "tributary_id": 1,
            "resource_identifier": "s3://test-bucket/eng/clean-uploads/",
            "access_pattern": "read"
        }
    ] with data.user_attributes as [
        {"user_id": 1, "attribute_key": "user_status", "attribute_value": "active"},
        {"user_id": 2, "attribute_key": "user_status", "attribute_value": "active"},
        {"user_id": 3, "attribute_key": "user_status", "attribute_value": "quarantine"}
    ]
}

test_deny_write_to_unauthorized_resource if {
    not cape.allow with input as {
        "user": {"id": 2},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/eng/raw-uploads/file.csv"
        }
    } with data.user_tributaries as [
        {"user_id": 1, "tributary_id": 1},
        {"user_id": 1, "tributary_id": 2},
        {"user_id": 2, "tributary_id": 2}
    ] with data.resources as [
        {
            "id": 1,
            "tributary_id": 1,
            "resource_identifier": "s3://test-bucket/eng/raw-uploads/",
            "access_pattern": "write"
        },
        {
            "id": 2,
            "tributary_id": 1,
            "resource_identifier": "s3://test-bucket/eng/clean-uploads/",
            "access_pattern": "read"
        }
    ] with data.user_attributes as [
        {"user_id": 1, "attribute_key": "user_status", "attribute_value": "active"},
        {"user_id": 2, "attribute_key": "user_status", "attribute_value": "active"}
    ]
}

test_deny_quarantined_user if {
    not cape.allow with input as {
        "user": {"id": 3},
        "action": "write",
        "resource": {
            "type": "s3",
            "path": "s3://test-bucket/ds/raw-uploads/file.csv"
        }
    } with data.user_attributes as [
        {"user_id": 3, "attribute_key": "user_status", "attribute_value": "quarantine"}
    ]
}
