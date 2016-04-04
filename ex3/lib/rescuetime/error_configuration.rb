module Rescuetime
  ErrorConfiguration = [
    { matcher: '# key not found', eid: :invalid_api_key },
    { matcher: 'format_date', eid: :invalid_date }
  ]
end
