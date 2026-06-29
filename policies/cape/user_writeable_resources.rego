package cape

import rego.v1

user_writeable_resources contains resource_info if {
    membership := data.user_tributaries[_]
    membership.user_id == input.user_id
    
    tributary := data.tributaries[_]
    tributary.id == membership.tributary_id
    
    resource := data.resources[_]
    resource.tributary_id == tributary.id
    resource.access_pattern == "write"
    
    resource_info := {
        "resource_identifier": resource.resource_identifier,
        "resource_type": resource.resource_type,
        "tributary_id": tributary.id,
        "tributary_name": tributary.name,
        "metadata": resource.metadata
    }
}
