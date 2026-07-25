#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

if ARGV.length != 1
  warn "usage: validate_xcstrings_json.rb AppHost/Localizable.xcstrings"
  exit 64
end

path = ARGV[0]

begin
  data = JSON.parse(File.read(path))
rescue Errno::ENOENT
  warn "FAIL: file not found: #{path}"
  exit 66
rescue JSON::ParserError => e
  warn "FAIL: invalid JSON: #{e.message}"
  exit 65
end

errors = []

source_language = data["sourceLanguage"]
strings = data["strings"]

errors << "missing top-level sourceLanguage" unless source_language.is_a?(String) && !source_language.empty?
errors << "missing top-level strings object" unless strings.is_a?(Hash)

if strings.is_a?(Hash)
  strings.each do |key, value|
    unless value.is_a?(Hash)
      errors << "#{key}: entry is not an object"
      next
    end

    localizations = value["localizations"]
    unless localizations.is_a?(Hash)
      errors << "#{key}: missing localizations object"
      next
    end

    %w[en uk].each do |language|
      unit = localizations.dig(language, "stringUnit")
      translated_value = unit && unit["value"]
      if !unit.is_a?(Hash)
        errors << "#{key}: missing #{language}.stringUnit"
      elsif !translated_value.is_a?(String) || translated_value.empty?
        errors << "#{key}: missing #{language} string value"
      end
    end
  end
end

if errors.empty?
  puts "OK: #{path}"
  puts "sourceLanguage: #{source_language}"
  puts "keys: #{strings.length}"
  exit 0
else
  warn "FAIL: #{path}"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
