package types

const (
	// ModuleName defines the module name
	ModuleName = "medasdigital"

	// StoreKey defines the primary module store key
	StoreKey = ModuleName

	// MemStoreKey defines the in-memory store key
	MemStoreKey = "mem_medasdigital"
)

var (
	ParamsKey = []byte("p_medasdigital")
)

func KeyPrefix(p string) []byte {
	return []byte(p)
}
