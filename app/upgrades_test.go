package app

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUpgradesAreWellFormed(t *testing.T) {
	seen := make(map[string]bool)
	for _, u := range Upgrades {
		require.NotEmpty(t, u.UpgradeName)
		require.NotNil(t, u.CreateUpgradeHandler, u.UpgradeName)
		require.False(t, seen[u.UpgradeName], "duplicate upgrade name %q", u.UpgradeName)
		seen[u.UpgradeName] = true
	}
}
