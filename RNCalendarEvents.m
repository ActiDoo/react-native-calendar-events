#import "RNCalendarEvents.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import <EventKit/EventKit.h>

@interface RNCalendarEvents ()
@property (nonatomic, strong) EKEventStore *eventStore;
@property (nonatomic) BOOL isAccessToEventStoreGranted;
@end

static NSString *const _id = @"id";
static NSString *const _externalId = @"externalId";
static NSString *const _calendarId = @"calendarId";
static NSString *const _title = @"title";
static NSString *const _location = @"location";
static NSString *const _startDate = @"startDate";
static NSString *const _endDate = @"endDate";
static NSString *const _allDay = @"allDay";
static NSString *const _notes = @"notes";
static NSString *const _url = @"url";
static NSString *const _alarms = @"alarms";
static NSString *const _recurrence = @"recurrence";
static NSString *const _recurrenceRule = @"recurrenceRule";
static NSString *const _occurrenceDate = @"occurrenceDate";
static NSString *const _creationDate = @"creationDate";
static NSString *const _lastModifiedDate = @"lastModifiedDate";
static NSString *const _isDetached = @"isDetached";
static NSString *const _availability = @"availability";
static NSString *const _attendees = @"attendees";
static NSString *const _organizer = @"organizer";

@implementation RNCalendarEvents

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

#pragma mark -
#pragma mark Event Store Initialize

- (EKEventStore *)eventStore
{
    if (!_eventStore) {
        _eventStore = [[EKEventStore alloc] init];
    }
    return _eventStore;
}

#pragma mark -
#pragma mark Event Store Authorization

- (NSString *)authorizationStatusForEventStore
{
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

    switch (status) {
        case EKAuthorizationStatusDenied:
            self.isAccessToEventStoreGranted = NO;
            return @"denied";
        case EKAuthorizationStatusRestricted:
            self.isAccessToEventStoreGranted = NO;
            return @"restricted";
        case EKAuthorizationStatusAuthorized:
            self.isAccessToEventStoreGranted = YES;
            return @"authorized";
        case EKAuthorizationStatusNotDetermined: {
            return @"undetermined";
        }
    }
}

#pragma mark -
#pragma mark Event Store Accessors

- (NSDictionary *)buildAndSaveEvent:(NSDictionary *)details
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    EKEvent *calendarEvent = nil;
    NSString *calendarId = [RCTConvert NSString:details[_calendarId]];
    NSString *eventId = [RCTConvert NSString:details[_id]];
    NSString *externalEventId = [RCTConvert NSString:details[_externalId]];
    NSString *title = [RCTConvert NSString:details[_title]];
    NSString *location = [RCTConvert NSString:details[_location]];
    NSDate *startDate = [RCTConvert NSDate:details[_startDate]];
    NSDate *endDate = [RCTConvert NSDate:details[_endDate]];
    NSNumber *allDay = [RCTConvert NSNumber:details[_allDay]];
    NSString *notes = [RCTConvert NSString:details[_notes]];
    NSString *url = [RCTConvert NSString:details[_url]];
    NSArray *alarms = [RCTConvert NSArray:details[_alarms]];
    NSString *recurrence = [RCTConvert NSString:details[_recurrence]];
    NSDictionary *recurrenceRule = [RCTConvert NSDictionary:details[_recurrenceRule]];
    NSString *availability = [RCTConvert NSString:details[_availability]];

    if (eventId) {
        calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    } else if (externalEventId) {
        calendarEvent = (EKEvent *)[self.eventStore calendarItemsWithExternalIdentifier:externalEventId];
    } else {
        calendarEvent = [EKEvent eventWithEventStore:self.eventStore];
        calendarEvent.calendar = [self.eventStore defaultCalendarForNewEvents];

        if (calendarId) {
            EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];

            if (calendar) {
                calendarEvent.calendar = calendar;
            }
        }
    }

    if (title) {
        calendarEvent.title = title;
    }

    if (location) {
        calendarEvent.location = location;
    }

    if (startDate) {
        calendarEvent.startDate = startDate;
    }

    if (endDate) {
        calendarEvent.endDate = endDate;
    }

    if (allDay) {
        calendarEvent.allDay = [allDay boolValue];
    }

    if (notes) {
        calendarEvent.notes = notes;
    }

    if (alarms) {
        calendarEvent.alarms = [self createCalendarEventAlarms:alarms];
    }

    if (recurrence) {
        EKRecurrenceRule *rule = [self createRecurrenceRule:recurrence interval:0 occurrence:0 endDate:nil];
        if (rule) {
            calendarEvent.recurrenceRules = [NSArray arrayWithObject:rule];
        }
    }

    if (recurrenceRule) {
        NSString *frequency = [RCTConvert NSString:recurrenceRule[@"frequency"]];
        NSInteger interval = [RCTConvert NSInteger:recurrenceRule[@"interval"]];
        NSInteger occurrence = [RCTConvert NSInteger:recurrenceRule[@"occurrence"]];
        NSDate *endDate = [RCTConvert NSDate:recurrenceRule[@"endDate"]];

        EKRecurrenceRule *rule = [self createRecurrenceRule:frequency interval:interval occurrence:occurrence endDate:endDate];
        if (rule) {
            calendarEvent.recurrenceRules = [NSArray arrayWithObject:rule];
        }
    }


    if (availability) {
        calendarEvent.availability = [self availablilityConstantMatchingString:availability];
    }

    NSURL *URL = [NSURL URLWithString:[url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
    if (URL) {
        calendarEvent.URL = URL;
    }

    return [self saveEvent:calendarEvent];
}

- (NSDictionary *)saveEvent:(EKEvent *)calendarEvent
{
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null], @"error": [NSNull null]}];

    NSError *error = nil;
    BOOL success = [self.eventStore saveEvent:calendarEvent span:EKSpanFutureEvents commit:YES error:&error];

    if (!success) {
        [response setValue:[error.userInfo valueForKey:@"NSLocalizedDescription"] forKey:@"error"];
    } else {
        [response setValue:calendarEvent.calendarItemIdentifier forKey:@"success"];
    }
    return [response copy];
}

- (NSDictionary *)findById:(NSString *)eventId
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null]}];

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    if (calendarEvent) {
        [response setValue:[self serializeCalendarEvent:calendarEvent] forKey:@"success"];
    }
    return [response copy];
}

- (NSDictionary *)deleteEvent:(NSString *)eventId span:(EKSpan)span
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null], @"error": [NSNull null]}];

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    NSError *error = nil;
    BOOL success = [self.eventStore removeEvent:calendarEvent span:span commit:YES error:&error];

    if (!success) {
        [response setValue:[error.userInfo valueForKey:@"NSLocalizedDescription"] forKey:@"error"];
    } else {
        [response setValue:@YES forKey:@"success"];
    }
    return [response copy];
}

#pragma mark -
#pragma mark Alarms

- (EKAlarm *)createCalendarEventAlarm:(NSDictionary *)alarm
{
    EKAlarm *calendarEventAlarm = nil;
    id alarmDate = [alarm valueForKey:@"date"];

    if ([alarmDate isKindOfClass:[NSString class]]) {
        calendarEventAlarm = [EKAlarm alarmWithAbsoluteDate:[RCTConvert NSDate:alarmDate]];
    } else if ([alarmDate isKindOfClass:[NSNumber class]]) {
        int minutes = [alarmDate intValue];
        calendarEventAlarm = [EKAlarm alarmWithRelativeOffset:(60 * minutes)];
    } else {
        calendarEventAlarm = [[EKAlarm alloc] init];
    }

    if ([alarm objectForKey:@"structuredLocation"] && [[alarm objectForKey:@"structuredLocation"] count]) {
        NSDictionary *locationOptions = [alarm valueForKey:@"structuredLocation"];
        NSDictionary *geo = [locationOptions valueForKey:@"coords"];
        CLLocation *geoLocation = [[CLLocation alloc] initWithLatitude:[[geo valueForKey:@"latitude"] doubleValue]
                                                             longitude:[[geo valueForKey:@"longitude"] doubleValue]];

        calendarEventAlarm.structuredLocation = [EKStructuredLocation locationWithTitle:[locationOptions valueForKey:@"title"]];
        calendarEventAlarm.structuredLocation.geoLocation = geoLocation;
        calendarEventAlarm.structuredLocation.radius = [[locationOptions valueForKey:@"radius"] doubleValue];

        if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"enter"]) {
            calendarEventAlarm.proximity = EKAlarmProximityEnter;
        } else if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"leave"]) {
            calendarEventAlarm.proximity = EKAlarmProximityLeave;
        } else {
            calendarEventAlarm.proximity = EKAlarmProximityNone;
        }
    }
    return calendarEventAlarm;
}

- (NSArray *)createCalendarEventAlarms:(NSArray *)alarms
{
    NSMutableArray *calendarEventAlarms = [[NSMutableArray alloc] init];
    for (NSDictionary *alarm in alarms) {
        if ([alarm count] && ([alarm valueForKey:@"date"] || [alarm objectForKey:@"structuredLocation"])) {
            EKAlarm *reminderAlarm = [self createCalendarEventAlarm:alarm];
            [calendarEventAlarms addObject:reminderAlarm];
        }
    }
    return [calendarEventAlarms copy];
}

- (void)addCalendarEventAlarm:(NSString *)eventId alarm:(NSDictionary *)alarm
{
    if (!self.isAccessToEventStoreGranted) {
        return;
    }

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    EKAlarm *calendarEventAlarm = [self createCalendarEventAlarm:alarm];
    [calendarEvent addAlarm:calendarEventAlarm];

    [self saveEvent:calendarEvent];
}

- (void)addCalendarEventAlarms:(NSString *)eventId alarms:(NSArray *)alarms
{
    if (!self.isAccessToEventStoreGranted) {
        return;
    }

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    calendarEvent.alarms = [self createCalendarEventAlarms:alarms];

    [self saveEvent:calendarEvent];
}

#pragma mark -
#pragma mark RecurrenceRules

-(EKRecurrenceFrequency)frequencyMatchingName:(NSString *)name
{
    EKRecurrenceFrequency recurrence = EKRecurrenceFrequencyDaily;

    if ([name isEqualToString:@"weekly"]) {
        recurrence = EKRecurrenceFrequencyWeekly;
    } else if ([name isEqualToString:@"monthly"]) {
        recurrence = EKRecurrenceFrequencyMonthly;
    } else if ([name isEqualToString:@"yearly"]) {
        recurrence = EKRecurrenceFrequencyYearly;
    }
    return recurrence;
}

-(EKRecurrenceRule *)createRecurrenceRule:(NSString *)frequency interval:(NSInteger)interval occurrence:(NSInteger)occurrence endDate:(NSDate *)endDate
{
    EKRecurrenceRule *rule = nil;
    EKRecurrenceEnd *recurrenceEnd = nil;
    NSInteger recurrenceInterval = 1;
    NSArray *validFrequencyTypes = @[@"daily", @"weekly", @"monthly", @"yearly"];

    if (frequency && [validFrequencyTypes containsObject:frequency]) {

        if (endDate) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:endDate];
        } else if (occurrence && occurrence > 0) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:occurrence];
        }

        if (interval > 1) {
            recurrenceInterval = interval;
        }

        rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:[self frequencyMatchingName:frequency]
                                                            interval:recurrenceInterval
                                                                 end:recurrenceEnd];
    }
    return rule;
}

-(NSString *)nameMatchingFrequency:(EKRecurrenceFrequency)frequency
{
    switch (frequency) {
        case EKRecurrenceFrequencyWeekly:
            return @"weekly";
        case EKRecurrenceFrequencyMonthly:
            return @"monthly";
        case EKRecurrenceFrequencyYearly:
            return @"yearly";
        default:
            return @"daily";
    }
}

#pragma mark -
#pragma mark Availability

- (NSMutableArray *)calendarSupportedAvailabilitiesFromMask:(EKCalendarEventAvailabilityMask)types
{
    NSMutableArray *availabilitiesStrings = [[NSMutableArray alloc] init];

    if(types & EKCalendarEventAvailabilityBusy) [availabilitiesStrings addObject:@"busy"];
    if(types & EKCalendarEventAvailabilityFree) [availabilitiesStrings addObject:@"free"];
    if(types & EKCalendarEventAvailabilityTentative) [availabilitiesStrings addObject:@"tentative"];
    if(types & EKCalendarEventAvailabilityUnavailable) [availabilitiesStrings addObject:@"unavailable"];

    return availabilitiesStrings;
}

- (NSString *)availabilityStringMatchingConstant:(EKEventAvailability)constant
{
    switch(constant) {
        case EKEventAvailabilityNotSupported:
            return @"notSupported";
        case EKEventAvailabilityBusy:
            return @"busy";
        case EKEventAvailabilityFree:
            return @"free";
        case EKEventAvailabilityTentative:
            return @"tentative";
        case EKEventAvailabilityUnavailable:
            return @"unavailable";
        default:
            return @"notSupported";
    }
}

- (EKEventAvailability)availablilityConstantMatchingString:(NSString *)string
{
    if([string isEqualToString:@"busy"]) {
        return EKEventAvailabilityBusy;
    }

    if([string isEqualToString:@"free"]) {
        return EKEventAvailabilityFree;
    }

    if([string isEqualToString:@"tentative"]) {
        return EKEventAvailabilityTentative;
    }

    if([string isEqualToString:@"unavailable"]) {
        return EKEventAvailabilityUnavailable;
    }

    return EKEventAvailabilityNotSupported;
}
                                                          
#pragma mark -
#pragma mark enum2string
- (NSString *)participantRoleStringMatchingConstant:(EKParticipantRole)constant
    {
        switch(constant) {
            case EKParticipantRoleChair:
                return @"char";
            case EKParticipantRoleOptional:
                return @"optional";
            case EKParticipantRoleRequired:
                return @"required";
            case EKParticipantRoleNonParticipant:
                return @"nonParticipant";
            case EKParticipantRoleUnknown:
                return @"unknown";
            default:
                return @"unknown";
        }
    }
                
- (NSString *)participantTypeStringMatchingConstant:(EKParticipantType)constant
{
  switch(constant) {
      case EKParticipantTypeRoom:
          return @"room";
      case EKParticipantTypeGroup:
          return @"group";
      case EKParticipantTypePerson:
          return @"person";
      case EKParticipantTypeUnknown:
          return @"unknown";
      case EKParticipantTypeResource:
          return @"resource";
      default:
          return @"unknown";
  }
}
                           
- (NSString *)participantStatusStringMatchingConstant:(EKParticipantStatus)constant
    {
        switch(constant) {
            case EKParticipantStatusPending:
                return @"pending";
            case EKParticipantStatusUnknown:
                return @"unknown";
            case EKParticipantStatusAccepted:
                return @"accepted";
            case EKParticipantStatusDeclined:
                return @"declined";
            case EKParticipantStatusCompleted:
                return @"completed";
            case EKParticipantStatusDelegated:
                return @"delegated";
            case EKParticipantStatusInProcess:
                return @"inProcess";
            case EKParticipantStatusTentative:
                return @"tentative";
            default:
                return @"unknown";
        }
    }



- (NSString *)weekDayStringMatchingConstants:(EKWeekday) constant
{
    switch(constant) {
        case EKWeekdaySaturday:
            return @"saturday";
        case EKWeekdaySunday:
            return @"sunday";
        case EKWeekdayMonday:
            return @"monday";
        case EKWeekdayTuesday:
            return @"tuesday";
        case EKWeekdayWednesday:
            return @"wednesday";
        case EKWeekdayThursday:
            return @"thursday";
        case EKWeekdayFriday:
            return @"friday";
        default:
            return @"unknown";
    }
}


#pragma mark -
#pragma mark Serializers

- (NSArray *)serializeCalendarEvents:(NSArray *)calendarEvents
{
    NSMutableArray *serializedCalendarEvents = [[NSMutableArray alloc] init];

    for (EKEvent *event in calendarEvents) {

        [serializedCalendarEvents addObject:[self serializeCalendarEvent:event]];
    }

    return [serializedCalendarEvents copy];
}

- (NSDictionary *)serializeCalendarEvent:(EKEvent *)event
{

    NSDictionary *emptyCalendarEvent = @{
                                         _title: @"",
                                         _location: @"",
                                         _startDate: @"",
                                         _endDate: @"",
                                         _allDay: @NO,
                                         _notes: @"",
                                         _url: @"",
                                         _alarms: [NSArray array],
                                         _recurrence: @"",
                                         _recurrenceRule: @{
                                                 @"frequency": @"",
                                                 @"interval": @"",
                                                 @"occurrence": @"",
                                                 @"endDate": @"",
                                                 @"firstDayOfTheWeek": @"",
                                                 @"daysOfTheMonth": [NSArray array],
                                                 @"daysOfTheYear": [NSArray array],
                                                 @"weeksOfTheYear": [NSArray array],
                                                 @"monthsOfTheYear": [NSArray array],
                                                 @"daysOfTheWeek": [NSArray array]
                                                 },
                                         _availability: @"",
                                         _attendees: [NSArray array],
                                         _organizer: [NSDictionary dictionary],
                                         };

    //firstDayOfTheWeek, daysOfTheMonth, daysOfTheYear, weeksOfTheYear, monthsOfTheYear, daysOfTheWeek
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z"];


    NSMutableDictionary *formedCalendarEvent = [NSMutableDictionary dictionaryWithDictionary:emptyCalendarEvent];

    if (event.calendarItemIdentifier) {
        [formedCalendarEvent setValue:event.calendarItemIdentifier forKey:_id];
    }

    if (event.calendarItemExternalIdentifier) {
        [formedCalendarEvent setValue:event.calendarItemExternalIdentifier forKey:_externalId];
    }

    if (event.calendar) {
        [formedCalendarEvent setValue:@{
                                        @"id": event.calendar.calendarIdentifier,
                                        @"title": event.calendar.title,
                                        @"source": event.calendar.source.title,
                                        @"allowsModifications": @(event.calendar.allowsContentModifications),
                                        @"allowedAvailabilities": [self calendarSupportedAvailabilitiesFromMask:event.calendar.supportedEventAvailabilities],
                                        }
                               forKey:@"calendar"];
    }

    if (event.title) {
        [formedCalendarEvent setValue:event.title forKey:_title];
    }

    if (event.notes) {
        [formedCalendarEvent setValue:event.notes forKey:_notes];
    }

    if (event.URL) {
        [formedCalendarEvent setValue:[event.URL absoluteString] forKey:_url];
    }

    if (event.location) {
        [formedCalendarEvent setValue:event.location forKey:_location];
    }

    if (event.hasAlarms) {
        NSMutableArray *alarms = [[NSMutableArray alloc] init];

        for (EKAlarm *alarm in event.alarms) {

            NSMutableDictionary *formattedAlarm = [[NSMutableDictionary alloc] init];
            NSString *alarmDate = nil;

            if (alarm.absoluteDate) {
                alarmDate = [dateFormatter stringFromDate:alarm.absoluteDate];
            } else if (alarm.relativeOffset) {
                NSDate *calendarEventStartDate = nil;
                if (event.startDate) {
                    calendarEventStartDate = event.startDate;
                } else {
                    calendarEventStartDate = [NSDate date];
                }
                alarmDate = [dateFormatter stringFromDate:[NSDate dateWithTimeInterval:alarm.relativeOffset
                                                                             sinceDate:calendarEventStartDate]];
            }
            [formattedAlarm setValue:alarmDate forKey:@"date"];

            if (alarm.structuredLocation) {
                NSString *proximity = nil;
                switch (alarm.proximity) {
                    case EKAlarmProximityEnter:
                        proximity = @"enter";
                        break;
                    case EKAlarmProximityLeave:
                        proximity = @"leave";
                        break;
                    default:
                        proximity = @"None";
                        break;
                }
                [formattedAlarm setValue:@{
                                           @"title": alarm.structuredLocation.title,
                                           @"proximity": proximity,
                                           @"radius": @(alarm.structuredLocation.radius),
                                           @"coords": @{
                                                   @"latitude": @(alarm.structuredLocation.geoLocation.coordinate.latitude),
                                                   @"longitude": @(alarm.structuredLocation.geoLocation.coordinate.longitude)
                                                   }}
                                  forKey:@"structuredLocation"];

            }
            [alarms addObject:formattedAlarm];
        }
        [formedCalendarEvent setValue:alarms forKey:_alarms];
    }

    if (event.startDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.startDate] forKey:_startDate];
    }

    if (event.endDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.endDate] forKey:_endDate];
    }

    if (event.occurrenceDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.occurrenceDate] forKey:_occurrenceDate];
    }

    if (event.creationDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.creationDate] forKey:_creationDate];
    }

    if (event.lastModifiedDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.lastModifiedDate] forKey:_lastModifiedDate];
    }
    
    if (event.organizer) {
        NSMutableDictionary *formattedParticipant = [[NSMutableDictionary alloc] init];
        
        [formattedParticipant setValue:(event.organizer.name) forKey:@"name"];
        [formattedParticipant setValue:([self participantRoleStringMatchingConstant:event.organizer.participantRole]) forKey:@"participantRole"];
        [formattedParticipant setValue:[self participantTypeStringMatchingConstant:event.organizer.participantType] forKey:@"participantType"];
        [formattedParticipant setValue:[self participantStatusStringMatchingConstant:event.organizer.participantStatus] forKey:@"participantStatus"];
        if(event.organizer.URL) {
            [formattedParticipant setValue:(event.organizer.URL.resourceSpecifier) forKey:@"url"];
        }
        [formattedParticipant setValue:[NSNumber numberWithBool:event.organizer.isCurrentUser] forKey:@"isCurrentUser"];
        
        [formedCalendarEvent setValue:formattedParticipant forKey:_organizer];
    }

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.isDetached] forKey:_isDetached];

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.allDay] forKey:_allDay];

    if (event.hasRecurrenceRules) {
        EKRecurrenceRule *rule = [event.recurrenceRules objectAtIndex:0];
        NSString *frequencyType = [self nameMatchingFrequency:[rule frequency]];
        [formedCalendarEvent setValue:frequencyType forKey:_recurrence];

        NSMutableDictionary *recurrenceRule = [NSMutableDictionary dictionaryWithDictionary:@{@"frequency": frequencyType}];

        if ([rule interval]) {
            [recurrenceRule setValue:@([rule interval]) forKey:@"interval"];
        }

        if ([[rule recurrenceEnd] endDate]) {
            [recurrenceRule setValue:[dateFormatter stringFromDate:[[rule recurrenceEnd] endDate]] forKey:@"endDate"];
        }

        if ([[rule recurrenceEnd] occurrenceCount]) {
            [recurrenceRule setValue:@([[rule recurrenceEnd] occurrenceCount]) forKey:@"occurrence"];
        }
        
        if ([rule firstDayOfTheWeek]) {
            [recurrenceRule setValue:@([rule firstDayOfTheWeek]) forKey:@"firstDayOfTheWeek"];
        }
        
        if ([rule daysOfTheMonth] != nil) {
            NSArray *daysOfTheMonth = [NSArray arrayWithArray:[rule daysOfTheMonth]];
            [recurrenceRule setValue:daysOfTheMonth forKey:@"daysOfTheMonth"];
        }
        
        if ([rule daysOfTheYear] != nil) {
            NSArray *daysOfTheYear = [NSArray arrayWithArray:[rule daysOfTheYear]];
            [recurrenceRule setValue:daysOfTheYear forKey:@"daysOfTheYear"];
        }
        
        if ([rule weeksOfTheYear] != nil) {
            NSArray *weeksOfTheYear = [NSArray arrayWithArray:[rule weeksOfTheYear]];
            [recurrenceRule setValue:weeksOfTheYear forKey:@"weeksOfTheYear"];
        }
        
        if ([rule monthsOfTheYear] != nil) {
            NSArray *monthsOfTheYear = [NSArray arrayWithArray:[rule monthsOfTheYear]];
            [recurrenceRule setValue:monthsOfTheYear forKey:@"monthsOfTheYear"];
        }
        
        if ([rule daysOfTheWeek] != nil) {
            NSArray *daysOfTheWeek = [NSArray arrayWithArray:[rule daysOfTheWeek]];
            NSMutableArray *daysOfTheWeekForJson = [NSMutableArray array];
            for(EKRecurrenceDayOfWeek *dow in daysOfTheWeek) {
                NSMutableDictionary *day = [NSMutableDictionary dictionary];
                [day setValue:@([dow weekNumber]) forKey:@"weeknumber"];
                EKWeekday wk = [dow dayOfTheWeek];
                [day setValue:[self weekDayStringMatchingConstants:wk] forKey:@"weekday"];
                //[day setValue:[dow ] forKey:@"weeknumber"];
                [daysOfTheWeekForJson addObject:day];
            }
            [recurrenceRule setValue:daysOfTheWeekForJson forKey:@"daysOfTheWeek"];
        }

        [formedCalendarEvent setValue:recurrenceRule forKey:_recurrenceRule];
    }

    [formedCalendarEvent setValue:[self availabilityStringMatchingConstant:event.availability] forKey:_availability];
    
    if (event.hasAttendees) {
        NSMutableArray *attendees = [[NSMutableArray alloc] init];
        
        for (EKParticipant *participant in event.attendees) {
            
            NSMutableDictionary *formattedParticipant = [[NSMutableDictionary alloc] init];
            
            [formattedParticipant setValue:(participant.name) forKey:@"name"];
            [formattedParticipant setValue:([self participantRoleStringMatchingConstant:participant.participantRole]) forKey:@"participantRole"];
            [formattedParticipant setValue:[self participantTypeStringMatchingConstant:participant.participantType] forKey:@"participantType"];
            [formattedParticipant setValue:[self participantStatusStringMatchingConstant:participant.participantStatus] forKey:@"participantStatus"];
            if(participant.URL) {
                [formattedParticipant setValue:(participant.URL.resourceSpecifier) forKey:@"url"];
            }
            [formattedParticipant setValue:[NSNumber numberWithBool:participant.isCurrentUser] forKey:@"isCurrentUser"];
            
            [attendees addObject:formattedParticipant];
        }
        
        [formedCalendarEvent setValue:attendees forKey:_attendees];
    }

    return [formedCalendarEvent copy];
}

#pragma mark -
#pragma mark RCT Exports

RCT_EXPORT_METHOD(authorizationStatus:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *status = [self authorizationStatusForEventStore];
    if (status) {
        resolve(status);
    } else {
        reject(@"error", @"authorization status error", nil);
    }
}

RCT_EXPORT_METHOD(authorizeEventStore:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    __weak RNCalendarEvents *weakSelf = self;
    [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *status = granted ? @"authorized" : @"denied";
            weakSelf.isAccessToEventStoreGranted = granted;
            if (!error) {
                resolve(status);
            } else {
                reject(@"error", @"authorization request error", error);
            }
        });
    }];
}

RCT_EXPORT_METHOD(findCalendars:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSArray* calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];

    if (!calendars) {
        reject(@"error", @"error finding calendars", nil);
    } else {
        NSMutableArray *eventCalendars = [[NSMutableArray alloc] init];
        for (EKCalendar *calendar in calendars) {
            [eventCalendars addObject:@{
                                        @"id": calendar.calendarIdentifier,
                                        @"title": calendar.title,
                                        @"allowsModifications": @(calendar.allowsContentModifications),
                                        @"source": calendar.source.title,
                                        @"allowedAvailabilities": [self calendarSupportedAvailabilitiesFromMask:calendar.supportedEventAvailabilities]
                                        }];
        }
        resolve(eventCalendars);
    }
}

RCT_EXPORT_METHOD(fetchAllEvents:(NSDate *)startDate endDate:(NSDate *)endDate calendars:(NSArray *)calendars resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSMutableArray *eventCalendars;

    if (calendars.count) {
        eventCalendars = [[NSMutableArray alloc] init];
        NSArray *deviceCalendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];

        for (EKCalendar *calendar in deviceCalendars) {
            if ([calendars containsObject:calendar.calendarIdentifier]) {
                [eventCalendars addObject:calendar];
            }
        }
    }

    NSPredicate *predicate = [self.eventStore predicateForEventsWithStartDate:startDate
                                                                      endDate:endDate
                                                                    calendars:eventCalendars];

    __weak RNCalendarEvents *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *calendarEvents = [[weakSelf.eventStore eventsMatchingPredicate:predicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (calendarEvents) {
                resolve([weakSelf serializeCalendarEvents:calendarEvents]);
              } else if (calendarEvents == nil) {
                resolve(@[]);
              } else {
                reject(@"error", @"calendar event request error", nil);
            }
        });
    });
}

RCT_EXPORT_METHOD(findEventById:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self findById:eventId];

    if (!response) {
        reject(@"error", @"error finding event", nil);
    } else {
        resolve([response valueForKey:@"success"]);
    }
}

RCT_EXPORT_METHOD(saveEvent:(NSString *)title details:(NSDictionary *)details resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:details];
    [options setValue:title forKey:_title];

    NSDictionary *response = [self buildAndSaveEvent:options];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

RCT_EXPORT_METHOD(removeEvent:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self deleteEvent:eventId span:EKSpanThisEvent];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

RCT_EXPORT_METHOD(removeFutureEvents:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self deleteEvent:eventId span:EKSpanFutureEvents];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

RCT_EXPORT_METHOD(createCalendar:(NSString*)calendarId widthTitle:(NSString*)title)
{
    EKCalendar *newCalendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:self.eventStore];
    newCalendar.title = title;

    EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];
    newCalendar.source = calendar.source;

    NSError *error = nil;
    [self.eventStore saveCalendar:newCalendar commit:YES error:&error];
}

@end
