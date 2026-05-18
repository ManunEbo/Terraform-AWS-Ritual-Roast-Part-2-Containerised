"use client";

import React, { useState, useEffect } from "react";
import Image from "next/image";
import Link from "next/link";

const Header = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);

  // Prevent scrolling when mobile menu is open
  useEffect(() => {
    if (isMenuOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = 'unset';
    }
  }, [isMenuOpen]);

  const navLinks = (
    <>
      <Link
        href="/"
        className="text-lg font-semibold transition-colors hover:opacity-80"
        style={{ color: "var(--brown-dark)" }}
        onClick={() => setIsMenuOpen(false)}
      >
        Home
      </Link>
      <Link
        href="/recipes"
        className="text-lg font-semibold transition-colors hover:text-[#4d3a33]"
        style={{ color: "var(--gold-dark)" }}
        onClick={() => setIsMenuOpen(false)}
      >
        Recipes
      </Link>
      <Link
        href="/contact"
        className="text-lg font-semibold transition-colors hover:text-[#4d3a33]"
        style={{ color: "#d47a45" }}
        onClick={() => setIsMenuOpen(false)}
      >
        Contact
      </Link>
    </>
  );

  return (
    <>
      <header
        className="w-full bg-white relative z-50 shadow-sm"
        style={{ fontFamily: "var(--font-montserrat-alternates)" }}
      >
        {/* Decorative Top Bar */}
        <div className="flex items-center w-full">
          <div className="flex-1 h-3 bg-[color:var(--brown-dark)]"></div>
          <div className="flex-1 h-3 bg-[color:var(--gold)]"></div>
          <div className="flex-1 h-3 bg-[color:var(--brown-dark)]"></div>
        </div>

        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-24">
            <div className="flex-shrink-0">
              <Link href="/" className="block">
                <Image
                  src="/images/rr-logo.png"
                  alt="Ritual Roast Logo"
                  width={180}
                  height={60}
                  priority // Critical for LCP: Loads the logo immediately
                  className="w-auto h-auto"
                />
              </Link>
            </div>

            {/* Desktop Navigation */}
            <div className="hidden md:flex items-center space-x-8">
              <nav className="flex items-center space-x-6">{navLinks}</nav>
              <button
                className="px-6 py-2 border rounded-lg text-lg font-semibold transition-all hover:bg-[color:var(--gold)] hover:text-white"
                style={{
                  borderColor: "var(--gold)",
                  color: "var(--gold-dark)",
                }}
              >
                Login
              </button>
              <div className="flex items-center space-x-3">
                <Link href="#" className="hover:scale-110 transition-transform">
                  <Image src="/images/social-fb.png" alt="Facebook" width={28} height={28} />
                </Link>
                <Link href="#" className="hover:scale-110 transition-transform">
                  <Image src="/images/social-twitter.png" alt="Twitter" width={28} height={28} />
                </Link>
                <Link href="#" className="hover:scale-110 transition-transform">
                  <Image src="/images/social-insta.png" alt="Instagram" width={28} height={28} />
                </Link>
              </div>
            </div>

            {/* Mobile Menu Button */}
            <div className="md:hidden">
              <button
                onClick={() => setIsMenuOpen(!isMenuOpen)}
                aria-expanded={isMenuOpen}
                aria-label="Toggle menu"
                className="p-2"
              >
                <svg
                  className="h-8 w-8 text-[color:var(--brown-dark)]"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  {isMenuOpen ? (
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  ) : (
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16m-7 6h7" />
                  )}
                </svg>
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Mobile Menu Panel */}
      <div
        className={`fixed top-0 right-0 h-full w-72 bg-white shadow-2xl z-[60] transform transition-transform duration-300 ease-in-out md:hidden ${
          isMenuOpen ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <div className="flex flex-col p-8 h-full">
          <button 
            className="self-end p-2 mb-8"
            onClick={() => setIsMenuOpen(false)}
          >
            <svg className="h-8 w-8 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
          
          <nav className="flex flex-col space-y-8 text-center">{navLinks}</nav>
          
          <div className="mt-auto space-y-8 pb-12">
            <button
              className="w-full py-3 border rounded-lg text-lg font-semibold"
              style={{ borderColor: "var(--gold)", color: "var(--gold-dark)" }}
            >
              Login
            </button>
            <div className="flex justify-center space-x-6">
              <Link href="#"><Image src="/images/social-fb.png" alt="FB" width={32} height={32} /></Link>
              <Link href="#"><Image src="/images/social-twitter.png" alt="Twitter" width={32} height={32} /></Link>
              <Link href="#"><Image src="/images/social-insta.png" alt="Insta" width={32} height={32} /></Link>
            </div>
          </div>
        </div>
      </div>

      {/* Overlay */}
      {isMenuOpen && (
        <div
          className="fixed inset-0 bg-black/60 backdrop-blur-sm z-[55] md:hidden"
          onClick={() => setIsMenuOpen(false)}
        ></div>
      )}
    </>
  );
};

export default Header;