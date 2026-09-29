package keeper

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"medasdigital/x/medasdigital/types"
)

// The notary queries are stubs until the notary logic is implemented
// (docs/notary-spec.md).

func (k Keeper) Commit(_ context.Context, _ *types.QueryCommitRequest) (*types.QueryCommitResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (k Keeper) Commits(_ context.Context, _ *types.QueryCommitsRequest) (*types.QueryCommitsResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (k Keeper) CommitsByHash(_ context.Context, _ *types.QueryCommitsByHashRequest) (*types.QueryCommitsByHashResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}

func (k Keeper) CommitsByCreator(_ context.Context, _ *types.QueryCommitsByCreatorRequest) (*types.QueryCommitsByCreatorResponse, error) {
	return nil, status.Error(codes.Unimplemented, "not implemented")
}
