class_name FormatService
extends RefCounted

## Locale-independent integer-safe formatting helpers for UI and reports.


static func format_time(minute_of_day: int) -> String:
	var m: int = posmod(minute_of_day, 1440)
	var hours: int = m / 60
	var mins: int = m % 60
	return "%02d:%02d" % [hours, mins]


static func format_minute_of_day(minute_of_day: int) -> String:
	return format_time(minute_of_day)


static func is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if is_leap_year(year) else 28
		_:
			return 30


static func day_to_calendar(day_num: int, start_year: int = 2026) -> Dictionary:
	var rem: int = maxi(1, day_num) - 1
	var y: int = start_year
	var m: int = 1
	while true:
		var dim: int = days_in_month(y, m)
		if rem < dim:
			var d: int = rem + 1
			return {
				"year": y,
				"month": m,
				"day": d,
				"days_in_month": dim,
				"days_remaining_in_month": dim - d + 1,
			}
		rem -= dim
		m += 1
		if m > 12:
			m = 1
			y += 1
	return {"year": start_year, "month": 1, "day": 1, "days_in_month": 31, "days_remaining_in_month": 31}


static func format_calendar_date(day_num: int, locale: String = "zh_CN") -> String:
	var cal: Dictionary = day_to_calendar(day_num)
	var y: int = int(cal["year"])
	var m: int = int(cal["month"])
	var d: int = int(cal["day"])
	if locale == "en":
		var months: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
		return "%s %d, %d" % [months[clampi(m - 1, 0, 11)], d, y]
	return "%d年%d月%d日" % [y, m, d]


static func format_bps(bps: int, show_sign: bool = false) -> String:
	var neg_v: int = bps if bps < 0 else -bps
	var whole: int = -(neg_v / 100)
	var frac: int = -(neg_v % 100)
	var prefix: String = ""
	if bps < 0:
		prefix = "-"
	elif bps > 0 and show_sign:
		prefix = "+"
	return "%s%d.%02d%%" % [prefix, whole, frac]


static func format_rate_bps(bps: int, show_sign: bool = false) -> String:
	return format_bps(bps, show_sign)


static func _currency_symbol(currency_code: String) -> String:
	match currency_code.to_upper():
		"CNY":
			return "¥"
		"USD":
			return "$"
		"JPY":
			return "¥"
		"EUR":
			return "€"
		_:
			return "¥"


static func _group_thousands(num_val: int) -> String:
	var raw: String = str(maxi(0, num_val))
	var out: String = ""
	var count: int = 0
	for i in range(raw.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = raw[i] + out
		count += 1
	return out


static func format_money(
	amount_minor: int,
	currency_code: String = "CNY",
	show_sign: bool = false,
	_locale: String = "zh_CN"
) -> String:
	var sym: String = _currency_symbol(currency_code)
	var neg_v: int = amount_minor if amount_minor < 0 else -amount_minor
	var major: int = -(neg_v / 100)
	var cents: int = -(neg_v % 100)
	var prefix: String = ""
	if amount_minor < 0:
		prefix = "-"
	elif amount_minor > 0 and show_sign:
		prefix = "+"
	return "%s%s%s.%02d" % [prefix, sym, _group_thousands(major), cents]


static func format_currency(
	amount_minor: int,
	currency_code: String = "CNY",
	show_sign: bool = false,
	locale: String = "zh_CN"
) -> String:
	return format_money(amount_minor, currency_code, show_sign, locale)


static func format_money_compact(
	amount_minor: int,
	currency_code: String = "CNY",
	show_sign: bool = false,
	locale: String = "zh_CN"
) -> String:
	var neg_v: int = amount_minor if amount_minor < 0 else -amount_minor
	if neg_v > -100_000:
		return format_money(amount_minor, currency_code, show_sign, locale)
	var sym: String = _currency_symbol(currency_code)
	var prefix: String = ""
	if amount_minor < 0:
		prefix = "-"
	elif amount_minor > 0 and show_sign:
		prefix = "+"

	var unit_div: int = 100_000
	var suffix: String = "K"
	if neg_v <= -100_000_000_000:
		unit_div = 100_000_000_000
		suffix = "B"
	elif neg_v <= -100_000_000:
		unit_div = 100_000_000
		suffix = "M"

	# Round half-up to 1 decimal place without multiplying abs_v by 10
	var tenth_div: int = unit_div / 10
	var scaled_tenths: int = -(neg_v / tenth_div)
	var rem: int = -(neg_v % tenth_div)
	if rem >= tenth_div / 2:
		scaled_tenths += 1
	var whole: int = scaled_tenths / 10
	var tenth: int = scaled_tenths % 10
	return "%s%s%d.%d%s" % [prefix, sym, whole, tenth, suffix]


static func format_signed_delta(
	delta_minor: int,
	currency_code: String = "CNY",
	locale: String = "zh_CN"
) -> String:
	return format_money(delta_minor, currency_code, true, locale)


static func format_day(day: int, locale: String = "zh_CN") -> String:
	match locale:
		"en":
			return "Day %d" % day
		"ja":
			return "%d日目" % day
		_:
			return "第%d天" % day
