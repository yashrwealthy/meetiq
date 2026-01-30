import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class UserProfile {
  final String name;
  final String userID;
  final String? crn;
  final String? relationship;
  final String? accountType;
  final String? panNumber;
  final String? phoneNumber;
  final String? email;
  final double investedValue;
  final double currentValue;
  final double absoluteReturn;
  final double absoluteReturnPercent;
  final double? xirr;

  UserProfile({
    required this.name,
    required this.userID,
    this.crn,
    this.relationship,
    this.accountType,
    this.panNumber,
    this.phoneNumber,
    this.email,
    required this.investedValue,
    required this.currentValue,
    required this.absoluteReturn,
    required this.absoluteReturnPercent,
    this.xirr,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? 'Unknown',
      userID: json['userID'] as String? ?? '',
      crn: json['crn'] as String?,
      relationship: json['relationship'] as String?,
      accountType: json['accountType'] as String?,
      panNumber: json['panNumber'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      investedValue: (json['investedValue'] as num?)?.toDouble() ?? 0.0,
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0.0,
      absoluteReturn: (json['absoluteReturn'] as num?)?.toDouble() ?? 0.0,
      absoluteReturnPercent: (json['absoluteReturnPercent'] as num?)?.toDouble() ?? 0.0,
      xirr: (json['xirr'] as num?)?.toDouble(),
    );
  }

  /// Create a demo profile for testing
  factory UserProfile.demo() {
    return UserProfile(
      name: 'Rahul Sharma',
      userID: 'CLT-DEMO-00001',
      phoneNumber: '+91 98765 43210',
      accountType: 'Moderate Risk',
      investedValue: 850000,
      currentValue: 972500,
      absoluteReturn: 122500,
      absoluteReturnPercent: 14.4,
    );
  }
}

class GraphQLService {
  static const String _baseUrl = 'https://graph.buildwealth.in/graphql/';

  static const String _userProfileQuery = '''
    query userPanFamilyProfile {
      userProfileView {
        name
        userID
        crn
        relationship
        accountType
        accountSubType
        panNumber
        phoneNumber
        email
        myProfiles {
          ...PanFamilyProfile
          __typename
        }
        familyProfiles {
          ...PanFamilyProfile
          __typename
        }
        mfProfileInfo {
          ...SegmentInfo
          __typename
        }
        familyProfilesInfo {
          ...SegmentInfo
          __typename
        }
        __typename
      }
    }

    fragment PanFamilyProfile on MiniProfileViewNode {
      name
      userID
      crn
      relationship
      accountType
      accountSubType
      panNumber
      phoneNumber
      email
      investedValue
      currentValue
      absoluteReturn
      absoluteReturnPercent
      xirr
      __typename
    }

    fragment SegmentInfo on SegmentInfo {
      investedValue
      currentValue
      unrealisedGain
      absoluteReturns
      xirr
      costOfCurrentInvestment
      __typename
    }
  ''';

  Future<UserProfile?> fetchUserProfile({
    required String partnerToken,
    required String clientId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'accept': '*/*',
          'authorization': partnerToken,
          'content-type': 'application/json',
          'x-w-api-version': 'v1',
          'x-w-client-id': clientId,
        },
        body: jsonEncode({
          'operationName': 'userPanFamilyProfile',
          'variables': {},
          'query': _userProfileQuery,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userProfileView = data['data']?['userProfileView'] as Map<String, dynamic>?;

        if (userProfileView != null) {
          // Try to get mfProfileInfo for portfolio values
          final mfProfileInfo = userProfileView['mfProfileInfo'] as Map<String, dynamic>?;

          return UserProfile(
            name: userProfileView['name'] as String? ?? 'Unknown',
            userID: userProfileView['userID'] as String? ?? '',
            crn: userProfileView['crn'] as String?,
            relationship: userProfileView['relationship'] as String?,
            accountType: userProfileView['accountType'] as String?,
            panNumber: userProfileView['panNumber'] as String?,
            phoneNumber: userProfileView['phoneNumber'] as String?,
            email: userProfileView['email'] as String?,
            investedValue: (mfProfileInfo?['investedValue'] as num?)?.toDouble() ?? 0.0,
            currentValue: (mfProfileInfo?['currentValue'] as num?)?.toDouble() ?? 0.0,
            absoluteReturn: (mfProfileInfo?['unrealisedGain'] as num?)?.toDouble() ?? 0.0,
            absoluteReturnPercent: (mfProfileInfo?['absoluteReturns'] as num?)?.toDouble() ?? 0.0,
            xirr: (mfProfileInfo?['xirr'] as num?)?.toDouble(),
          );
        }
      }

      debugPrint('GraphQL response: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('GraphQL error: $e');
      return null;
    }
  }
}
