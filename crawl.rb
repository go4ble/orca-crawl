require 'business_time'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'jsoner'
require 'mqtt'

DATE_FMT = '%m/%d/%Y %I:%M %p'

class Crawl
  include Capybara::DSL

  attr_reader :balance

  def initialize(username:, password:, card_number:, station:)
    @username    = username
    @password    = password
    @card_number = card_number
    @station     = station

    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, {
        phantomjs_options: ["--ignore-ssl-errors=yes", "--ssl-protocol=any", "--web-security=false"]
      })
    end

    Capybara.app_host = 'https://orcacard.com'
    Capybara.default_driver = ENV['DRIVER']&.to_sym || :poltergeist
    Capybara.run_server = false
  end

  def login
    visit('/')
    fill_in(id: 'main-username', with: @username)
    fill_in(id: 'head-password', with: @password)
    click_on(id: 'head-login')
  end

  def goto_card
    table = all('table', class: 'data').first
    json = Jsoner.parse(table['outerHTML'])
    card_row = JSON.parse(json).find { |row| @card_number == row['Card Number'].strip }
    raise 'could not find card' if card_row.nil?
    @balance = card_row['E-purse Balance'].strip
    click_on(text: @card_number)
    click_on(text: 'Transaction history')
  end

  def read_table_to_json(table)
    json = Jsoner.parse(table['outerHTML'])
    JSON.parse(json).map { |row| row.transform_keys(&:strip).transform_values(&:strip) }
  end

  def filter_morning_bordings(data)
    data.select { |row| /entry/i =~ row['Item'] && /#{@station}/i =~ row['Location'] }
  end

  def filter_this_month(data)
    this_month = Date.today.month
    data.select { |row| Date.strptime(row['Date / Time'], DATE_FMT).month == this_month }
  end

  def fetch_morning_bordings_this_month
    login
    balance = goto_card
    results = []
    loop do
      table = find('table', id: 'resultTable')
      results += read_table_to_json(table)
      next_link = all('a', text: 'Next').first
      if next_link.nil?
        break
      else
        next_link.click
      end
    end
    mornings = filter_morning_bordings(results)
    this_month = filter_this_month(mornings)
    this_month
  end
end

if __FILE__ == $0
  options = {
    username:    ENV['USERNAME']    || (raise 'USERNAME must be defined'),
    password:    ENV['PASSWORD']    || (raise 'PASSWORD must be defined'),
    card_number: ENV['CARD_NUMBER'] || (raise 'CARD_NUMBER must be defined'),
    station:     ENV['STATION']     || 'Auburn Station'
  }
  c = Crawl.new(options)
  results = c.fetch_morning_bordings_this_month
  count = results.length
  puts "#{count} boarding#{count == 1 ? '' : 's'} this month."
  days_remaining = Date.today.business_days_until(Date.today.next_month.beginning_of_month)
  puts "#{days_remaining} day#{days_remaining == 1 ? '' : 's'} remaining."
  puts "#{c.balance}"

  mqtt_host = ENV['MQTT_HOST']
  if mqtt_host
    mqtt_topic = "orca_crawl/#{options[:card_number]}"
    mqtt_payload = {
      boardings:      count,
      days_remaining: days_remaining,
      balance:        c.balance,
      checked_at:     Time.now.iso8601
    }.to_json
    puts "Publishing to MQTT topic: #{mqtt_topic}."
    MQTT::Client.connect(mqtt_host) do |client|
      # qos = 1, at least once
      client.publish(mqtt_topic, mqtt_payload, retain = true, qos = 1)
    end
  end
end
