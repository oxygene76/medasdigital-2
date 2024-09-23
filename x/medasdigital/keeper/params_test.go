package keeper_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	keepertest "medasdigital/testutil/keeper"
	"medasdigital/x/medasdigital/types"
)

func TestGetParams(t *testing.T) {
	k, ctx := keepertest.MedasdigitalKeeper(t)
	params := types.DefaultParams()

	require.NoError(t, k.SetParams(ctx, params))
	require.EqualValues(t, params, k.GetParams(ctx))
}
