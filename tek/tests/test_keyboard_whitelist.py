

def test_tk_record_key_aliases_normalize_to_supported_whitelist_keys():
    from tek.src.keyboard_whitelist import canonicalize_key
    assert canonicalize_key("space") == "SPACE"
    assert canonicalize_key("Control_L") == "CTRL"
    assert canonicalize_key("Shift_R") == "SHIFT"
    assert canonicalize_key("Return") == "ENTER"
    assert canonicalize_key("Escape") == "ESC"
