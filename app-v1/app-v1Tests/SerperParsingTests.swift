//
//  SerperParsingTests.swift
//  app-v1Tests
//
//  Verifies SerperClient.parse maps Serper's raw JSON (organic results,
//  people-also-ask, related searches) into our own clean WebSearchResponse
//  without leaking any Serper-specific shape.
//

import Foundation
import Testing
@testable import app_v1

@Suite struct SerperParsingTests {
    private let samplePayload = """
    {
        "searchParameters": { "q": "trending Bali beach dog hashtags", "type": "search", "engine": "google" },
        "organic": [
            { "title": "A moment for the beach dogs in Bali", "link": "https://www.instagram.com/p/DPh3qISkqnk/", "snippet": "Bali hits different with these beach buddies #balidoglovers #sesehbeach #beachdog #balivibes #islandlife", "position": 1 },
            { "title": "Dogs of Bali", "link": "https://www.facebook.com/61557982169766/videos/", "snippet": "#dog #pantai #bali #beach #balidog.", "position": 2 },
            { "title": "Hashtags - Maggielovesorbit.com", "link": "https://maggielovesorbit.com/favorite-hashtags-dogs/", "snippet": "Knowing how to find the top instagram hashtags for your dogs.", "position": 3 },
            { "title": "Bali Tourists Warned About Beach Dogs After Attack", "link": "https://thebalisun.com/bali-tourists-warned-about-beach-dogs-after-attack/", "snippet": "The local government regularly holds mass vaccination drives.", "position": 4 },
            { "title": "Top Dog Hashtags to Make Your Dog Insta-Famous", "link": "https://www.petfinder.com/dogs-and-puppies/", "snippet": "Learn how to use hashtags for your dog.", "position": 5 }
        ],
        "peopleAlsoAsk": [
            { "question": "What dog hashtag gets the most likes?", "title": "Dog Hashtags for Instagram Famous Dogs", "snippet": "#Dog. #DogsOfInstagram. #Puppy.", "link": "https://socialbuddy.com/dog-hashtags/" },
            { "question": "What is a good caption for a dog at the beach?", "title": "55 Best Beach Captions For Your Dog Photos", "snippet": "15 Inspirational Beach Captions.", "link": "https://www.sugarthegoldenretriever.com/" },
            { "question": "What are the top trending dog hashtags on Instagram?", "title": "The 15 popular dog hashtags for Instagram", "snippet": "#dogsofinstagram (433M) #dogs (344M)", "link": "https://www.instagram.com/reel/DGUrtYpRMkq/" },
            { "question": "What is Bali's slogan?", "title": "Destination Marketing Slogan for 2025", "snippet": "Bali, Your Way.", "link": "https://www.balihotelsassociation.com/" }
        ],
        "credits": 1
    }
    """

    @Test func mapsOrganicResultsWithTitleUrlSnippetPosition() throws {
        let data = Data(samplePayload.utf8)
        let response = try SerperClient.parse(data, query: "trending Bali beach dog hashtags")

        #expect(response.query == "trending Bali beach dog hashtags")
        let organic = response.results.prefix(5)
        #expect(organic.count == 5)
        #expect(organic.first?.title == "A moment for the beach dogs in Bali")
        #expect(organic.first?.url == "https://www.instagram.com/p/DPh3qISkqnk/")
        #expect(organic.first?.snippet.contains("#balidoglovers") == true)
        #expect(organic.map(\.position) == [1, 2, 3, 4, 5])
    }

    @Test func foldsPeopleAlsoAskInWithContinuingPositions() throws {
        let data = Data(samplePayload.utf8)
        let response = try SerperClient.parse(data, query: "trending Bali beach dog hashtags")

        // 5 organic + 4 people-also-ask
        #expect(response.results.count == 9)
        let paa = response.results.suffix(4)
        #expect(paa.map(\.position) == [6, 7, 8, 9])
        #expect(paa.first?.snippet.contains("#Dog") == true)
    }

    @Test func relatedQueriesIncludePeopleAlsoAskQuestions() throws {
        let data = Data(samplePayload.utf8)
        let response = try SerperClient.parse(data, query: "trending Bali beach dog hashtags")

        #expect(response.relatedQueries.contains("What dog hashtag gets the most likes?"))
        #expect(response.relatedQueries.contains("What are the top trending dog hashtags on Instagram?"))
    }

    @Test func decodesWhenOptionalBlocksAreMissing() throws {
        let minimal = """
        { "organic": [ { "title": "T", "link": "https://example.com", "snippet": "S", "position": 1 } ] }
        """
        let response = try SerperClient.parse(Data(minimal.utf8), query: "q")
        #expect(response.results.count == 1)
        #expect(response.relatedQueries.isEmpty)
    }
}
