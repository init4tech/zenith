## Zenith

![rust](https://github.com/init4tech/zenith/actions/workflows/test.yml/badge.svg) ![rust](https://github.com/init4tech/zenith/actions/workflows/cd.yml/badge.svg)
Solidity contracts for a next-gen rollup system.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```