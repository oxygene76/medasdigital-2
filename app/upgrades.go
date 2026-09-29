package app

import (
	"fmt"

	upgradetypes "cosmossdk.io/x/upgrade/types"

	"medasdigital/app/upgrades"
	v2 "medasdigital/app/upgrades/v2"
)

// Upgrades lists all software upgrades known to this binary. Never remove an
// upgrade that has been applied on mainnet: x/upgrade refuses to start a
// binary that lacks the handler of the last applied upgrade.
var Upgrades = []upgrades.Upgrade{
	v2.Upgrade,
}

// setUpgradeHandlers registers the handler of every upgrade in Upgrades.
// Must run after all modules (including the manually wired IBC and wasm
// modules) are in the module manager, because the handlers run migrations
// over app.ModuleManager.
func (app *App) setUpgradeHandlers() {
	for _, u := range Upgrades {
		app.UpgradeKeeper.SetUpgradeHandler(
			u.UpgradeName,
			u.CreateUpgradeHandler(app.ModuleManager, app.Configurator()),
		)
	}
}

// setUpgradeStoreLoader applies the StoreUpgrades of a pending upgrade on the
// first start of the new binary. x/upgrade writes upgrade-info.json to the
// node's data directory when the old binary halts at the upgrade height.
// Must run before app.Load(), which seals the BaseApp (SetStoreLoader panics
// afterwards).
func (app *App) setUpgradeStoreLoader() error {
	upgradeInfo, err := app.UpgradeKeeper.ReadUpgradeInfoFromDisk()
	if err != nil {
		return fmt.Errorf("failed to read upgrade info from disk: %w", err)
	}

	if upgradeInfo.Name == "" || app.UpgradeKeeper.IsSkipHeight(upgradeInfo.Height) {
		return nil
	}

	for _, u := range Upgrades {
		if u.UpgradeName == upgradeInfo.Name {
			storeUpgrades := u.StoreUpgrades
			app.SetStoreLoader(upgradetypes.UpgradeStoreLoader(upgradeInfo.Height, &storeUpgrades))
			return nil
		}
	}

	return nil
}
