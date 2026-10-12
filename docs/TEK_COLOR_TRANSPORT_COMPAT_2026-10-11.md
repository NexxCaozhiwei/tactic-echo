# TEK color transport compatibility

Inherited transport normalization supports standard and verified gamma 1.2
pairs with complete CRC/commit verification, preserving existing TEAP v3
and all foreground, Hook, BindingToken and SendInput gates. Codec tests cover
all bytes, catalog and binding-token envelopes, gaps, corrupt data, bounded
64-way quantization ambiguity and captured transport fixtures. The fixture
origin is historical; this is a self-contained transport compatibility suite,
not a dependency on any other AddOn or repository.
