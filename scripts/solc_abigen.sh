# script for solc/abigen solidity files
# below env variables are set by github action

# PRID: ${{ github.event.number }}
# BRANCH: ${{ github.head_ref }}
# GH_TOKEN: ${{ secrets.GH_TOKEN }}

SOLC_VER="v0.8.9+commit.e5eed63a"
OPENZEPPELIN="openzeppelin-contracts-4.2.0"          # if change, also need to change the url in dld_solc
GETH_VER="geth-alltools-linux-amd64-1.10.3-991384a7" # for abigen
CNTRDIR="contracts"                                  # folder name for all contracts code

# xx.sol under contracts/, no need for .sol suffix, if sol file is in subfolder, just add the relative path
solFiles=(
  Broker
  ShareToken
  strategies/compound/StrategyCompound
)

dld_solc() {
  # curl -L "https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-${SOLC_VER}" -o solc && chmod +x solc
  # sudo mv solc /usr/local/bin/
  # only need oz's contracts subfolder, files will be at $CNTRDIR/$OPENZEPPELIN/contracts
  curl -L "https://github.com/OpenZeppelin/openzeppelin-contracts/archive/v4.2.0.tar.gz" | tar -xz -C $CNTRDIR $OPENZEPPELIN/contracts/
}

dld_abigen() {
  curl -sL https://gethstore.blob.core.windows.net/builds/$GETH_VER.tar.gz | sudo tar -xz -C /usr/local/bin --strip 1 $GETH_VER/abigen
  sudo chmod +x /usr/local/bin/abigen
}

# MUST run this under repo root
# will generate a single combined.json under $CNTRDIR
run_solc() {
  pushd $CNTRDIR
  solc --base-path $PWD --allow-paths . --overwrite --optimize --optimize-runs 800 --pretty-json --combined-json abi,bin -o . '@openzeppelin/'=$OPENZEPPELIN/ \
    $(for f in ${solFiles[@]}; do echo -n "$f.sol "; done)
  no_openzeppelin combined.json # combined.json file name is hardcoded in solc
  popd
}

# remove openzeppelin from combined.json. solc will also include all openzeppelin in combined.json but we don't want to generate go for them
# $1 is the json file from solc output
no_openzeppelin() {
  jq '."contracts"|=with_entries(select(.key|test("^openzeppelin")|not))' $1 >tmp.json
  mv tmp.json $1
}

# MUST run this under contract repo root
run_abigen() {
  mkdir -p eth
  abigen -combined-json ./$CNTRDIR/combined.json -pkg contracts -out eth/combined.go
}