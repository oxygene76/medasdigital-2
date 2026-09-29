package types_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"medasdigital/x/medasdigital/types"
)

func TestParamsValidate(t *testing.T) {
	tests := []struct {
		desc   string
		params types.Params
		valid  bool
	}{
		{"default", types.DefaultParams(), true},
		{"minimum values", types.NewParams(1, 0), true},
		{"maximum values", types.NewParams(65536, 1024), true},
		{"payload limit zero", types.NewParams(0, 128), false},
		{"payload limit too large", types.NewParams(65537, 128), false},
		{"label limit too large", types.NewParams(16384, 1025), false},
	}
	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {
			err := tc.params.Validate()
			if tc.valid {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
		})
	}
}

func TestDefaultParams(t *testing.T) {
	p := types.DefaultParams()
	require.Equal(t, uint32(16384), p.MaxPayloadBytes)
	require.Equal(t, uint32(128), p.MaxLabelLength)
}
