package keeper

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"medasdigital/x/medasdigital/types"
)

// Commit is a stub until the notary logic is implemented (docs/notary-spec.md).
func (k msgServer) Commit(_ context.Context, _ *types.MsgCommit) (*types.MsgCommitResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

// Reveal is a stub until the notary logic is implemented (docs/notary-spec.md).
func (k msgServer) Reveal(_ context.Context, _ *types.MsgReveal) (*types.MsgRevealResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}
