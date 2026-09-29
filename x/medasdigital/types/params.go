package types

import (
	"fmt"

	paramtypes "github.com/cosmos/cosmos-sdk/x/params/types"
)

var _ paramtypes.ParamSet = (*Params)(nil)

// Parameter defaults and bounds, see docs/notary-spec.md.
const (
	DefaultMaxPayloadBytes uint32 = 16384
	MinMaxPayloadBytes     uint32 = 1
	MaxMaxPayloadBytes     uint32 = 65536

	DefaultMaxLabelLength uint32 = 128
	MaxMaxLabelLength     uint32 = 1024
)

// ParamKeyTable the param key table for launch module
func ParamKeyTable() paramtypes.KeyTable {
	return paramtypes.NewKeyTable().RegisterParamSet(&Params{})
}

// NewParams creates a new Params instance
func NewParams(maxPayloadBytes, maxLabelLength uint32) Params {
	return Params{
		MaxPayloadBytes: maxPayloadBytes,
		MaxLabelLength:  maxLabelLength,
	}
}

// DefaultParams returns a default set of parameters
func DefaultParams() Params {
	return NewParams(DefaultMaxPayloadBytes, DefaultMaxLabelLength)
}

// ParamSetPairs get the params.ParamSet
func (p *Params) ParamSetPairs() paramtypes.ParamSetPairs {
	return paramtypes.ParamSetPairs{}
}

// Validate validates the set of params
func (p Params) Validate() error {
	if p.MaxPayloadBytes < MinMaxPayloadBytes || p.MaxPayloadBytes > MaxMaxPayloadBytes {
		return fmt.Errorf("max_payload_bytes must be between %d and %d, got %d",
			MinMaxPayloadBytes, MaxMaxPayloadBytes, p.MaxPayloadBytes)
	}
	if p.MaxLabelLength > MaxMaxLabelLength {
		return fmt.Errorf("max_label_length must be between 0 and %d, got %d",
			MaxMaxLabelLength, p.MaxLabelLength)
	}
	return nil
}
