// Copyright 2026 The Oa Authors
#ifndef OA_PUBLIC_LIVE_CALENDAR_H_
#define OA_PUBLIC_LIVE_CALENDAR_H_

#include <functional>
#include <string>
#include <vector>

namespace oa {

struct LiveCalendarCapture {
  bool signed_out = false;
  std::vector<std::string> event_payloads;
};

// Loads Google Calendar in a temporary cookie-seeded off-the-record page and
// captures its event JSON responses via DevTools, as Arc's LiveCalendarClient.
void FetchLiveCalendar(const std::string& profile_id,
                       int account_number,
                       std::function<void(LiveCalendarCapture)> done);

}  // namespace oa

#endif  // OA_PUBLIC_LIVE_CALENDAR_H_
