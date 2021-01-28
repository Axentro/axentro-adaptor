# Copyright © 2017-2021 The Axentro Core developers
#
# See the LICENSE file at the top-level directory of this distribution
# for licensing information.
#
# Unless otherwise agreed in a custom licensing agreement with the Axentro Core developers,
# no part of this software, including this file, may be copied, modified,
# propagated, or distributed except according to the terms contained in the
# LICENSE file.
#
# Removal or modification of this copyright notice is prohibited.

require "kemal"
require "json"
require "router"
require "axentro-util"
require "option_parser"
require "baked_file_system"
require "./crypto"
require "./virtual_file_system/*"

wallet = nil
node_url = nil
app_port = nil
app_host = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: "

  parser.on("-p PORT", "--port=PORT", "The port to start the app on e.g. -p 8001 (defaults to port 8008)") do |port|
    app_port = port
  end

  parser.on("-b BIND", "--bind=BIND", "The host to start the app on e.g -b 192.0.145.1 (defaults to localhost)") do |host|
    app_host = host
  end

  parser.on("-w WALLET", "--wallet=WALLET", "Provide a wallet to send all transactions from") do |w|
    wallet = w
  end

  parser.on("-n URL", "--node=URL", "Provide the node to connect to e.g. https://mainnet.axentro.io") do |n|
    node_url = n
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

struct TransactionRequest
  include JSON::Serializable
  property from_address : String
  property from_public_key : String
  property to_address : String
  property wif : String
  property amount : String
end

struct MinimalTransactionRequest
  include JSON::Serializable
  property to_address : String
  property amount : String
end

struct Wallet
  include JSON::Serializable
  property public_key : String
  property wif : String
  property address : String
end

struct HdWallet
  include JSON::Serializable
  property public_key : String
  property wif : String
  property address : String
  property derivation : String
end

class WebServer
  include Router

  @wallet : Wallet?

  def initialize(@node_url : String?, @wallet_path : String?, @app_host : String?, @app_port : String?)
    @wallet = load_wallet
  end

  private def load_wallet
    return if @wallet_path.nil?
    _wallet_path = @wallet_path.not_nil!
    raise "failed to find wallet at #{_wallet_path}, create it first!" unless File.exists?(_wallet_path)
    begin
      Wallet.from_json(File.read(_wallet_path))
    rescue e
      raise e.message || "unknown wallet error"
    end
  end

  def draw_routes
    get "/" do |context, params|
      context.response.headers["Content-Type"] = "text/html"
      context.response << FileStorage.get("/index.html").gets_to_end
      context
    end

    post "/transaction/send-from-wallet" do |context, params|
      if @node_url.nil? || @wallet.nil?
        result = {status: "error", result: "to use this endpoint you must start this app with --node=some-node-url --wallet=path/to/wallet.json"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        onParams(context, MinimalTransactionRequest) do |request|
          wallet = @wallet.not_nil!
          transaction = Axentro::Util.create_signed_send_transaction(wallet.address, wallet.public_key, wallet.wif, request.to_address, request.amount)
          transaction_id = Axentro::Util.post_transaction(transaction, @node_url.not_nil!)

          if transaction_id.nil?
            result = {status: "error", result: "error sending transaction to host: #{@node_url.not_nil!}, check the logs"}.to_json
            context.response.status_code = 500
          else
            result = {status: "success", result: {transaction: transaction_id}}.to_json
          end

          context.response.print result
          context
        end
      end
    end

    post "/transaction/signed-from-wallet" do |context, params|
      if @wallet.nil?
        result = {status: "error", result: "to use this endpoint you must start this app with --wallet=path/to/wallet.json"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        onParams(context, MinimalTransactionRequest) do |request|
          wallet = @wallet.not_nil!
          transaction = Axentro::Util.create_signed_send_transaction(wallet.address, wallet.public_key, wallet.wif, request.to_address, request.amount)
          result = {status: "success", result: {transaction: transaction}}.to_json

          context.response.print result
          context
        end
      end
    end

    post "/transaction/send" do |context, params|
      if _node_url = @node_url
        onParams(context, TransactionRequest) do |request|
          transaction = Axentro::Util.create_signed_send_transaction(request.from_address, request.from_public_key, request.wif, request.to_address, request.amount)
          transaction_id = Axentro::Util.post_transaction(transaction, _node_url)

          if transaction_id.nil?
            result = {status: "error", result: "error sending transaction to host: #{_node_url}, check the logs"}.to_json
            context.response.status_code = 500
          else
            result = {status: "success", result: {transaction: transaction_id}}.to_json
          end

          context.response.print result
          context
        end
      else
        result = {status: "error", result: "to use this endpoint you must start this app with --node=some-node-url"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      end
    end

    post "/transaction/signed" do |context, params|
      if _node_url = @node_url
        onParams(context, TransactionRequest) do |request|
          transaction = Axentro::Util.create_signed_send_transaction(request.from_address, request.from_public_key, request.wif, request.to_address, request.amount)

          result = {status: "success", result: JSON.parse(transaction)}.to_json
          context.response.print result
          context
        end
      else
        result = {status: "error", result: "to use this endpoint you must start this app with --node=some-node-url"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      end
    end

    get "/wallet/create/:amount" do |context, params|
      if params["amount"].nil?
        result = {status: "error", result: "you must supply the amount e.g. wallet/create/12"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        amount = params["amount"].not_nil!.to_i
        generated_wallets = (1..amount).map { |n| generate_standard_wallet }
        result = {status: "success", result: {wallets: generated_wallets}}.to_json
        context.response.print result
        context
      end
    end

    get "/wallet/hd/create/:amount" do |context, params|
      if params["amount"].nil?
        result = {status: "error", result: "you must supply the amount e.g. wallet/hd/create/12"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        amount = params["amount"].not_nil!.to_i
        context.response.print generate_multi_hd_wallets(amount).to_json
        context
      end
    end

    get "/wallet/hd/from_seed/:seed/amount/:amount/from_derivation/:derivation" do |context, params|
      if params["amount"].nil? || params["seed"].nil? || params["derivation"].nil?
        result = {status: "error", result: "you must supply the seed, derivation and amount, derivation is e.g. 1`"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        seed = params["seed"].not_nil!
        derivation_start = params["derivation"].not_nil!.to_i
        amount = params["amount"].not_nil!.to_i
        context.response.print generate_hd_wallets(seed, amount, derivation_start).to_json
        context
      end
    end

    get "/address/validate/:address" do |context, params|
      if params["address"].nil?
        result = {status: "error", result: "you must supply the wallet address`"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      else
        address = params["address"].not_nil!
        is_valid_address = Address.is_valid?(address)
        result = {status: "success", result: {is_valid: is_valid_address}}.to_json
        context.response.print result
        context
      end
    end

    get "/hra/validate/:hra" do |context, params|
      if _node_url = @node_url
        if params["hra"].nil?
          result = {status: "error", result: "you must supply either an address or a human readable address`"}.to_json
          context.response.status_code = 500
          context.response.print result
          context
        else
          hra = params["hra"].not_nil!
          if hra.ends_with?(".ax")
            result = Crest.get("#{_node_url}/api/v1/hra/#{hra}")
            parsed = JSON.parse(result.body)
            is_valid = parsed["result"]["resolved"]
            result = {status: "success", result: {is_valid: is_valid}}.to_json
          else
            is_valid_address = Address.is_valid?(hra)
            result = {status: "success", result: {is_valid: is_valid_address}}.to_json
          end
          context.response.print result
          context
        end
      else
        result = {status: "error", result: "to use this endpoint you must start this app with --node=some-node-url"}.to_json
        context.response.status_code = 500
        context.response.print result
        context
      end
    end
  end

  def run
    server = HTTP::Server.new(route_handler)
    server_host = @app_host || "localhost"
    server_port = @app_port.try(&.to_i) || 8008
    server.bind_tcp(server_host, server_port)
    puts "Starting Axentro Adaptor server on http://#{server_host}:#{server_port}"
    server.listen
  end

  # ----- util -----
  def onParams(context, klass : T.class, &block) forall T
    yield klass.from_json(contextToJson(context))
  rescue e : Exception
    context.response.status_code = 500
    context.response.print %Q{{"result": "error", "message": "#{e.message || "unknow error"}"}}
    context.response.close
    context
  end

  def contextToJson(context)
    context.request.body.not_nil!.gets_to_end
  end

  # ---- wallet creation ----
  def generate_standard_wallet
    keys = KeyRing.generate

    {
      public_key: keys.public_key.as_hex,
      wif:        keys.wif.as_hex,
      address:    keys.address.as_hex,
    }
  end

  def generate_hd_wallet
    keys = KeyRing.generate_hd

    {seed:       keys.seed,
     derivation: "m/0'",
     public_key: keys.public_key.as_hex,
     wif:        keys.wif.as_hex,
     address:    keys.address.as_hex,
    }
  end

  def generate_multi_hd_wallets(amount)
    wallets = (1..amount).to_a.map do |n|
      derivation = "m/#{n}'"
      keys = KeyRing.generate_hd

      {seed:       keys.seed,
       derivation: "m/0'",
       public_key: keys.public_key.as_hex,
       wif:        keys.wif.as_hex,
       address:    keys.address.as_hex,
      }
    end
    {status: "success", result: {wallets: wallets}}
  end

  def generate_hd_wallets(seed, amount, derivation_start)
    wallets = (0..(Math.max(1, amount - 1))).to_a.map do |n|
      n = n + derivation_start
      derivation = "m/#{n}'"
      keys = KeyRing.generate_hd(seed, derivation)

      {
        derivation: derivation,
        public_key: keys.public_key.as_hex,
        wif:        keys.wif.as_hex,
        address:    keys.address.as_hex,
      }
    end
    {status: "success", result: {seed: seed, wallets: wallets}}
  end

  include Axentro::Core
  include Axentro::Core::Keys
end

web_server = WebServer.new(node_url, wallet, app_host, app_port)
web_server.draw_routes
web_server.run
