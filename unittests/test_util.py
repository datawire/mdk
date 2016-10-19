"""
Tests for utilities.
"""

from hypothesis import strategies as st
from hypothesis import given, assume

from mdk_util import versionMatch


positive_ints = st.integers(min_value=0, max_value=10000)
major = st.tuples(positive_ints)
major_minor = st.tuples(positive_ints, positive_ints)
major_minor_patch = st.tuples(positive_ints, positive_ints, positive_ints)


def match(version_tuple1, version_tuple2):
    return versionMatch(_join(version_tuple1), _join(version_tuple2))

def _join(ints):
    return ".".join(str(i) for i in ints)

@given(major_minor, major_minor)
def test_differentMajor(version1, version2):
    """
    Different major versions never match.
    """
    assume(version1[0] != version2[0])
    assert not match(version1, version2)
    assert not match(version1[:1], version2)
    assert not match(version1, version2[:1])
    assert not match(version1[:1], version2[:1])


@given(major_minor, positive_ints)
def test_smallerMinor(version, minor_increment):
    """
    A requested version that is smaller or equal in minor increment than the
    actual version will match.
    """
    larger_version = (version[0], version[1] + minor_increment)
    assert match(version, larger_version)
    assert match(version[:1], larger_version)
    # Patch support only for backwards compat:
    assert match(version + (1,), larger_version)
    assert match(version, larger_version + (1,))


@given(major_minor, st.integers(min_value=1, max_value=100))
def test_largerMinor(version, minor_increment):
    """
    A requested version that is larger in minor increment than the actual
    version will not match.
    """
    larger_version = (version[0], version[1] + minor_increment)
    assert not match(larger_version, version)
    assert not match(larger_version, version[:1])
    # Patch support only for backwards compat:
    assert not match(larger_version, version + (1,))
    assert not match(larger_version + (1,), version)


@given(major_minor_patch)
def test_patchIgnored(version):
    """
    The patch part of version is ignored.
    """
    assert match(version, version[:2] + (0,))
    assert match(version[:2] + (0,), version)

