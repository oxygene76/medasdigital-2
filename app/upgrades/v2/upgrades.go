// Package v2 contains the "v2" software upgrade.
//
// For now this is an empty upgrade: it only runs the module migrations, and
// since no ConsensusVersion changed, those are no-ops. It exists to exercise
// the upgrade path end to end before real changes are added.
package v2

import (
	"context"

	storetypes "cosmossdk.io/store/types"
	upgradetypes "cosmossdk.io/x/upgrade/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"

	"medasdigital/app/upgrades"
)

// UpgradeName is the name of the governance upgrade plan.
const UpgradeName = "v2"

var Upgrade = upgrades.Upgrade{
	UpgradeName:          UpgradeName,
	CreateUpgradeHandler: CreateUpgradeHandler,
	StoreUpgrades:        storetypes.StoreUpgrades{},
}

func CreateUpgradeHandler(mm *module.Manager, configurator module.Configurator) upgradetypes.UpgradeHandler {
	return func(ctx context.Context, plan upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
		logger := sdk.UnwrapSDKContext(ctx).Logger().With("upgrade", UpgradeName)
		logger.Info("running upgrade handler", "height", plan.Height)

		toVM, err := mm.RunMigrations(ctx, configurator, fromVM)
		if err != nil {
			return nil, err
		}

		logger.Info("upgrade handler finished", "modules", len(toVM))
		return toVM, nil
	}
}
