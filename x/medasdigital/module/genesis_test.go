package medasdigital_test

import (
	"testing"

	keepertest "medasdigital/testutil/keeper"
	"medasdigital/testutil/nullify"
	medasdigital "medasdigital/x/medasdigital/module"
	"medasdigital/x/medasdigital/types"

	"github.com/stretchr/testify/require"
)

func TestGenesis(t *testing.T) {
	genesisState := types.GenesisState{
		Params: types.DefaultParams(),

		// this line is used by starport scaffolding # genesis/test/state
	}

	k, ctx := keepertest.MedasdigitalKeeper(t)
	medasdigital.InitGenesis(ctx, k, genesisState)
	got := medasdigital.ExportGenesis(ctx, k)
	require.NotNil(t, got)

	nullify.Fill(&genesisState)
	nullify.Fill(got)

	// this line is used by starport scaffolding # genesis/test/assert
}
