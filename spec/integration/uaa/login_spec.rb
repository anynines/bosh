require 'spec_helper'

describe 'Logging into a director with UAA authentication', type: :integration do
  context 'with properly configured UAA' do
    with_reset_sandbox_before_each(user_authentication: 'uaa')

    before do
      bosh_runner.run("target #{current_sandbox.director_url}")
      bosh_runner.run('logout')
    end

    it 'logs in successfully' do
      bosh_runner.run_interactively("login --ca-cert #{current_sandbox.certificate_path}") do |runner|
        expect(runner).to have_output 'Email:'
        runner.send_keys 'marissa'
        expect(runner).to have_output 'Password:'
        runner.send_keys 'koala'
        expect(runner).to have_output 'One Time Code'
        runner.send_keys 'dontcare' # UAA only uses this for SAML, but always prompts for it
        expect(runner).to have_output "Logged in as `marissa'"
      end

      output = bosh_runner.run('status')
      expect(output).to match /marissa/
    end

    it 'fails to log in when incorrect credentials were provided' do
      bosh_runner.run_interactively("login --ca-cert #{current_sandbox.certificate_path}") do |runner|
        expect(runner).to have_output 'Email:'
        runner.send_keys 'fake'
        expect(runner).to have_output 'Password:'
        runner.send_keys 'fake'
        expect(runner).to have_output 'One Time Code'
        runner.send_keys 'dontcare'
        expect(runner).to have_output 'Failed to log in'
      end
      output = bosh_runner.run('status')
      expect(output).to match /not logged in/
    end
  end

  context 'when UAA is configured with wrong certificate' do
    with_reset_sandbox_before_each(user_authentication: 'uaa', ssl_mode: 'wrong-ca')

    before do
      bosh_runner.run("target #{current_sandbox.director_url}")
    end

    it 'fails to log in when incorrect credentials were provided' do
      bosh_runner.run_interactively("login --ca-cert #{current_sandbox.certificate_path}") do |runner|
        expect(runner).to have_output 'Invalid SSL Cert'
      end
    end
  end
end
