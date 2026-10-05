// Package upgrades contains the software upgrades of the chain. Each upgrade
// lives in its own sub-package (e.g. v2) and is registered in app/upgrades.go.
package upgrades

import (
	storetypes "cosmossdk.io/store/types"
	upgradetypes "cosmossdk.io/x/upgrade/types"
	"github.com/cosmos/cosmos-sdk/types/module"
)

// Upgrade describes a named software upgrade executed by x/upgrade.
type Upgrade struct {
	// UpgradeName must match the name of the governance upgrade plan.
	UpgradeName string

	// CreateUpgradeHandler returns the handler that runs at the upgrade height.
	CreateUpgradeHandler func(mm *module.Manager, configurator module.Configurator) upgradetypes.UpgradeHandler

	// StoreUpgrades lists KV stores added, renamed or deleted by this upgrade.
	StoreUpgrades storetypes.StoreUpgrades
}
