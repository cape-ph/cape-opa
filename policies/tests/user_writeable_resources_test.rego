package cape_test

import rego.v1
import data.cape

mock_tributaries := [
    {"id": 1, "name": "ENG"},
    {"id": 2, "name": "DS"}
]

mock_user_tributaries := [
    {"user_id": 1, "tributary_id": 1},
    {"user_id": 1, "tributary_id": 2},
    {"user_id": 2, "tributary_id": 2}
]

mock_resources := [
    {
        "id": 1,
        "tributary_id": 1,
        "resource_identifier": "s3://test-bucket/eng/raw-uploads/",
        "resource_type": "s3",
        "access_pattern": "write",
        "metadata": {}
    },
    {
        "id": 2,
        "tributary_id": 1,
        "resource_identifier": "s3://test-bucket/eng/clean-uploads/",
        "resource_type": "s3",
        "access_pattern": "read",
        "metadata": {}
    },
    {
        "id": 3,
        "tributary_id": 2,
        "resource_identifier": "s3://test-bucket/ds/raw-uploads/",
        "resource_type": "s3",
        "access_pattern": "write",
        "metadata": {}
    },
    {
        "id": 4,
        "tributary_id": 2,
        "resource_identifier": "s3://test-bucket/ds/clean-uploads/",
        "resource_type": "s3",
        "access_pattern": "read",
        "metadata": {}
    }
]

test_user_with_write_access_returns_resources if {
    result := cape.user_writeable_resources 
        with input as {"user_id": 1} 
        with data.tributaries as mock_tributaries
        with data.user_tributaries as mock_user_tributaries
        with data.resources as mock_resources
    count(result) == 2
}

test_user_with_no_write_access_returns_empty if {
    result := cape.user_writeable_resources 
        with input as {"user_id": 99} 
        with data.tributaries as mock_tributaries
        with data.user_tributaries as mock_user_tributaries
        with data.resources as mock_resources
    count(result) == 0
}

test_user_with_multiple_tributaries_returns_all_writable if {
    result := cape.user_writeable_resources 
        with input as {"user_id": 1} 
        with data.tributaries as mock_tributaries
        with data.user_tributaries as mock_user_tributaries
        with data.resources as mock_resources
    
    resource_ids := {r.resource_identifier | r := result[_]}
    resource_ids == {
        "s3://test-bucket/eng/raw-uploads/",
        "s3://test-bucket/ds/raw-uploads/"
    }
}

test_includes_tributary_metadata if {
    result := cape.user_writeable_resources 
        with input as {"user_id": 1} 
        with data.tributaries as mock_tributaries
        with data.user_tributaries as mock_user_tributaries
        with data.resources as mock_resources
    
    some r
    result[r]
    result[r].resource_identifier
    result[r].resource_type
    result[r].tributary_id
    result[r].tributary_name
    result[r].metadata
}
