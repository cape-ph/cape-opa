package cape

import rego.v1

default allow := false
default reason := "Access denied"

allow := false if {
    user_status := get_user_status(input.user.id)
    user_status in ["quarantine", "suspended", "deactivated"]
}

reason := "User account is not active" if {
    user_status := get_user_status(input.user.id)
    user_status in ["quarantine", "suspended", "deactivated"]
}

allow if {
    input.action == "write"
    user_writable(input.user.id, input.resource.path)
}

reason := "Write access granted via tributary membership" if {
    input.action == "write"
    user_writable(input.user.id, input.resource.path)
}

allow if {
    input.action == "read"
    user_readable(input.user.id, input.resource.path)
}

reason := "Read access granted via tributary membership" if {
    input.action == "read"
    user_readable(input.user.id, input.resource.path)
}

allow if {
    is_admin(input.user.id)
}

reason := "Admin access granted" if {
    is_admin(input.user.id)
}

user_writable(user_id, path) if {
    membership := data.user_tributaries[_]
    membership.user_id == user_id
    
    resource := data.resources[_]
    resource.tributary_id == membership.tributary_id
    resource.access_pattern == "write"
    
    startswith(path, resource.resource_identifier)
}

user_readable(user_id, path) if {
    membership := data.user_tributaries[_]
    membership.user_id == user_id
    
    resource := data.resources[_]
    resource.tributary_id == membership.tributary_id
    resource.access_pattern in ["read", "both"]
    
    startswith(path, resource.resource_identifier)
}

is_admin(user_id) if {
    attr := data.user_attributes[_]
    attr.user_id == user_id
    attr.attribute_key == "is_admin"
    attr.attribute_value == "true"
}

get_user_status(user_id) := status if {
    attr := data.user_attributes[_]
    attr.user_id == user_id
    attr.attribute_key == "user_status"
    status := attr.attribute_value
} else := "active"
