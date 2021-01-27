# Axentro Adatpor API
This is a local service you can run that provides a REST API that can do the following things:

* signed & send transactions
* create standard wallets
* create hd wallets
* validate an address
* validate a human readable address

### Using the API

When you start this application from the command line you can optionally supply:

* path/to/your-wallet.json
* url of a node

The following endpoints are available only when you supply both a node to connect to and a wallet

* transaction/send-from-wallet

The following endpoints are available only when you supply a wallet

* transaction/signed-from-wallet

The following endpoints are available only when you supply a node url 

* transaction/send
* hra/validate

## Installation

```bash
git clone https://github.com/Axentro/axentro-adaptor.git
cd axentro-adaptor
shards install
shards build --release --no-debug
```

## Usage

```bash
./bin/axentro-adaptor -p 8008
```
Then navigate to `http://localhost:8008` for the docs 

you can also optionally supply a connecting node and a local wallet. Some of the endpoints requires these.

```bash
./bin/axentro-adaptor -p 8008 -n https://mainnet.axentro.io -w path/to/wallet.json
```

you can also set the host and port e.g. 

```bash
./bin/axentro-adaptor -b 127.0.0.1 -p 8001
```


## Contributing

1. Fork it (<https://github.com/Axentro/axentro-adaptor/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Kingsley Hendrickse](https://github.com/kingsleyh) - creator and maintainer
